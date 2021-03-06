(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* $Id: arg.ml,v 1.1 1998/08/19 13:29:02 pessaux Exp $ *)

type spec =
  | Unit of (unit -> unit)     (* Call the function with unit argument *)
  | Set of bool ref            (* Set the reference to true *)
  | Clear of bool ref          (* Set the reference to false *)
  | String of (string -> unit) (* Call the function with a string argument *)
  | Int of (int -> unit)       (* Call the function with an int argument *)
  | Float of (float -> unit)   (* Call the function with a float argument *)
  | Rest of (string -> unit)   (* Stop interpreting keywords and call the
                                  function with each remaining argument *)
;;

exception Bad of string ;;

type error =
  | Unknown of string
  | Wrong of string * string * string  (* option, actual, expected *)
  | Missing of string
  | Message of string ;;


let rec assoc3 x l =
  match l with
  | [] -> raise Not_found
  | (y1, y2, y3)::t when y1 = x -> y2
  | _::t -> assoc3 x t
;;

let usage speclist errmsg =
  Printf.eprintf "%s\n" errmsg;
  List.iter (function (key, _, doc) ->
    Printf.eprintf "  %s %s\n" key doc) speclist
;;

let current = ref 0;;

let parse speclist anonfun errmsg =
  let initpos = !current in
  let stop error =
    let progname =
      if initpos < Array.length Sys.argv then Sys.argv.(initpos) else "(?)" in
    begin match error with
      | Unknown s when s = "-help" -> ()
      | Unknown s ->
          Printf.eprintf "%s: unknown option `%s'.\n" progname s
      | Missing s ->
          Printf.eprintf "%s: option `%s' needs an argument.\n" progname s
      | Wrong (opt, arg, expected) ->
          Printf.eprintf "%s: wrong argument `%s'; option `%s' expects %s.\n"
                  progname arg opt expected
      | Message s ->
          Printf.eprintf "%s: %s.\n" progname s
    end;
    usage speclist errmsg;
    exit 2;
  in
  let l = Array.length Sys.argv in
  incr current;
  while !current < l do
    let s = Sys.argv.(!current) in
    if String.length s >= 1 & String.get s 0 = '-' then begin
      let action =
        try assoc3 s speclist
        with Not_found -> stop (Unknown s)
      in
      begin try
        match action with
        | Unit f -> f ();
        | Set r -> r := true;
        | Clear r -> r := false;
        | String f when !current + 1 < l ->
            let arg = Sys.argv.(!current+1) in
            f arg;
            incr current;
        | Int f when !current + 1 < l ->
            let arg = Sys.argv.(!current+1) in
            begin try f (int_of_string arg)
            with Failure "int_of_string" -> stop (Wrong (s, arg, "an integer"))
            end;
            incr current;
        | Float f when !current + 1 < l ->
            let arg = Sys.argv.(!current+1) in
            f (float_of_string arg);
            incr current;
        | Rest f ->
            while !current < l-1 do
              f Sys.argv.(!current+1);
              incr current;
            done;
        | _ -> stop (Missing s)
      with Bad m -> stop (Message m);
      end;
      incr current;
    end else begin
      (try anonfun s with Bad m -> stop (Message m));
      incr current;
    end;
  done;
;;
