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

(* $Id: parsing.ml,v 1.3 1999/03/04 11:05:56 pessaux Exp $ *)

(* The parsing engine *)


(* Internal interface to the parsing engine *)
type parser_env =
  { mutable s_stack : int array;        (* States *)
    mutable v_stack : Obj.t array;      (* Semantic attributes *)
    mutable symb_start_stack : int array; (* Start positions *)
    mutable symb_end_stack : int array;   (* End positions *)
    mutable stacksize : int;            (* Size of the stacks *)
    mutable stackbase : int;            (* Base sp for current parse *)
    mutable curr_char : int;            (* Last token read *)
    mutable lval : Obj.t;               (* Its semantic attribute *)
    mutable symb_start : int;           (* Start pos. of the current symbol*)
    mutable symb_end : int;             (* End pos. of the current symbol *)
    mutable asp : int;                  (* The stack pointer for attributes *)
    mutable rule_len : int;             (* Number of rhs items in the rule *)
    mutable rule_number : int;          (* Rule number to reduce by *)
    mutable sp : int;                   (* Saved sp for parse_engine *)
    mutable state : int;                (* Saved state for parse_engine *)
    mutable errflag : int }             (* Saved error flag for parse_engine *)

type parse_tables =
  { actions : (parser_env -> Obj.t) array;
    transl_const : int array;
    transl_block : int array;
    lhs : string;
    len : string;
    defred : string;
    dgoto : string;
    sindex : string;
    rindex : string;
    gindex : string;
    tablesize : int;
    table : string;
    check : string;
    error_function : string -> unit }

exception YYexit of Obj.t
exception Parse_error

type parser_input =
    Start
  | Token_read
  | Stacks_grown_1
  | Stacks_grown_2
  | Semantic_action_computed
  | Error_detected

type parser_output =
    Read_token
  | Raise_parse_error
  | Grow_stacks_1
  | Grow_stacks_2
  | Compute_semantic_action
  | Call_error_function

external parse_engine :
    parse_tables[`a] <[`b]-> parser_env[`c] <[`d]-> parser_input[`e] <[`f]->
    Obj.t[`g] <[`h]-> parser_output[_] = "parse_engine" ;;

let env =
  { s_stack = Array.create 100 0;
    v_stack = Array.create 100 (Obj.repr ());
    symb_start_stack = Array.create 100 0;
    symb_end_stack = Array.create 100 0;
    stacksize = 100;
    stackbase = 0;
    curr_char = 0;
    lval = Obj.repr ();
    symb_start = 0;
    symb_end = 0;
    asp = 0;
    rule_len = 0;
    rule_number = 0;
    sp = 0;
    state = 0;
    errflag = 0 }

let grow_stacks() =
  let oldsize = env.stacksize in
  let newsize = oldsize * 2 in
  let new_s = Array.create newsize 0
  and new_v = Array.create newsize (Obj.repr ())
  and new_start = Array.create newsize 0
  and new_end = Array.create newsize 0 in
    Array.blit env.s_stack 0 new_s 0 oldsize;
    env.s_stack <- new_s;
    Array.blit env.v_stack 0 new_v 0 oldsize;
    env.v_stack <- new_v;
    Array.blit env.symb_start_stack 0 new_start 0 oldsize;
    env.symb_start_stack <- new_start;
    Array.blit env.symb_end_stack 0 new_end 0 oldsize;
    env.symb_end_stack <- new_end;
    env.stacksize <- newsize

let clear_parser() =
  Array.fill env.v_stack 0 env.stacksize (Obj.repr ());
  env.lval <- Obj.repr ()

let current_lookahead_fun = ref (fun (x: Obj.t) -> false)

let yyparse tables start lexer lexbuf =
  let rec loop cmd arg =
    match parse_engine tables env cmd arg with
      Read_token ->
        let t = Obj.repr(lexer lexbuf) in
        env.symb_start <- lexbuf.Lexing.lex_abs_pos + lexbuf.Lexing.lex_start_pos;
        env.symb_end   <- lexbuf.Lexing.lex_abs_pos + lexbuf.Lexing.lex_curr_pos;
        loop Token_read t
    | Raise_parse_error ->
        raise Parse_error
    | Compute_semantic_action ->
        let (action, value) =
          try
            (Semantic_action_computed, tables.actions.(env.rule_number) env)
          with Parse_error ->
            (Error_detected, Obj.repr ()) in
        loop action value
    | Grow_stacks_1 ->
        grow_stacks(); loop Stacks_grown_1 (Obj.repr ())
    | Grow_stacks_2 ->
        grow_stacks(); loop Stacks_grown_2 (Obj.repr ())
    | Call_error_function ->
        tables.error_function "syntax error";
        loop Error_detected (Obj.repr ()) in
  let init_asp = env.asp
  and init_sp = env.sp
  and init_stackbase = env.stackbase
  and init_state = env.state
  and init_curr_char = env.curr_char
  and init_errflag = env.errflag in
  env.stackbase <- env.sp + 1;
  env.curr_char <- start;
  try
    loop Start (Obj.repr ())
  with exn ->
    let curr_char = env.curr_char in
    env.asp <- init_asp;
    env.sp <- init_sp;
    env.stackbase <- init_stackbase;
    env.state <- init_state;
    env.curr_char <- init_curr_char;
    env.errflag <- init_errflag;
    match exn with
      YYexit v ->
        Obj.magic v
    | _ ->
        current_lookahead_fun :=
          (fun tok ->
            if Obj.is_block tok
            then tables.transl_block.(Obj.tag tok) = curr_char
            else tables.transl_const.(Obj.magic tok) = curr_char);
        raise exn

let peek_val env n =
  Obj.magic env.v_stack.(env.asp - n)

let symbol_start () =
  if env.rule_len > 0
  then env.symb_start_stack.(env.asp - env.rule_len + 1)
  else env.symb_end_stack.(env.asp)
let symbol_end () =
  env.symb_end_stack.(env.asp)

let rhs_start n =
  env.symb_start_stack.(env.asp - (env.rule_len - n))
let rhs_end n =
  env.symb_end_stack.(env.asp - (env.rule_len - n))

(* Protection Wrapper to localize accumulations due to the reference *)
exception ParsingWrapper of exn ;;
let is_current_lookahead tok =
  try (!current_lookahead_fun)(Obj.repr tok)
  with whatever -> raise (ParsingWrapper whatever)

let parse_error (msg: string) = ()

