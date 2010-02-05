(*
 * Copyright (c) 2009-2010
 *     Thomas Gazagnaire <thomas@gazagnaire.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Sql_backend

let global_count = ref 0

let clean_list : (unit -> unit) list ref = ref []
let flush_list : (string -> unit) list ref = ref []

let clean_all env name =
	debug (name ^ "*") env `Cache "cache" (Printf.sprintf "clean_all(%i)" (List.length !clean_list));
	List.iter (fun f -> f ()) !clean_list

let flush_all env name =
	debug (name ^ "*") env `Cache "cache" (Printf.sprintf "flush_all(%s,%i)" name (List.length !flush_list));
	List.iter (fun f -> f name) !flush_list

type ('a, 'b) t = {
	type_name : string;
	tbl : (string, 'a) Hashtbl.t;
	create : int -> 'a;
	to_weakid : 'a -> 'b -> int64;
	of_weakid : 'a -> int64 -> 'b list;
	mem : 'a -> 'b -> bool;
	mem_weakid : 'a -> int64 -> bool;
	add : 'a -> 'b -> int64 -> unit;
	remove : 'a -> 'b -> unit;
	replace : 'a -> 'b -> int64 -> unit;
	dump : 'a -> string;
}

let string_of_t string_of_a t =
	let tbls = Hashtbl.fold (fun db a acc -> (db, a) :: acc) t.tbl [] in
	let tbls = List.map (fun (db, a) -> Printf.sprintf "(%s, %s)" db (string_of_a a)) tbls in
	let tbl = String.concat "," tbls in
	Printf.sprintf "%s_cache={%s}" t.type_name tbl

module type Sig = sig
	type tbl
	type elt
	val create : string -> (tbl, elt) t
end

module Make (H : Hashtbl.HashedType) : Sig with type tbl = Weakid.Make(H).t and type elt = Weakid.Make(H).elt = struct

	module W = Weakid.Make(H)

	type tbl = W.t
	type elt = W.elt

	let clean t =
		let to_remove = ref [] in
		Hashtbl.iter (fun k v -> if W.length v = 0 then to_remove := k :: !to_remove) t.tbl;
		List.iter (fun k -> Hashtbl.remove t.tbl k) !to_remove

	let flush t name =
		Hashtbl.iter (fun k v -> if k = name then W.clear v) t.tbl

	let create name =
		let tbl = Hashtbl.create 32 in
		let t = {
			type_name = name;
			tbl = tbl;
			create = W.create;
			to_weakid = W.to_weakid;
			of_weakid = W.of_weakid;
			mem = W.mem;
			mem_weakid = W.mem_weakid;
			add = W.add;
			remove = W.remove;
			replace = W.replace;
			dump = W.dump;
		} in
		clean_list := (fun () -> clean t) :: !clean_list;
		flush_list := (flush t) :: !flush_list;
		t
end

let with_table env t db fn =
	incr global_count;
	if !global_count mod 10000 = 0 then clean_all env db;
	let tbl = 
		if Hashtbl.mem t.tbl db then
			Hashtbl.find t.tbl db
		else begin
			let w = t.create 128 in
			Hashtbl.replace t.tbl db w;
			w
		end in
	fn tbl

let debug env t db s =
	debug db env `Cache "cache" (Printf.sprintf "calling %s(%s) -- %s" s db (string_of_t t.dump t))

let to_weakid env t db elt =
	debug env t db "to_weakid";
	with_table env t db (fun tbl -> t.to_weakid tbl elt)
	
let of_weakid env t db id =
	debug env t db "of_weakid";
	with_table env t db (fun tbl -> t.of_weakid tbl id)

let mem env t db elt =
	debug env t db "mem";
	with_table env t db (fun tbl -> t.mem tbl elt)
	
let mem_weakid env t db id =
	debug env t db "mem_weakid";
	with_table env t db (fun tbl -> t.mem_weakid tbl id)

let add env t db elt =
	debug env t db "add";
	with_table env t db (fun tbl -> t.add tbl elt)

let remove env t db elt =
	debug env t db "remove";
	with_table env t db (fun tbl -> t.remove tbl elt)

let replace env t db elt id =
	debug env t db "replace";
	with_table env t db (fun tbl -> t.replace tbl elt id)
