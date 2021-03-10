(*****************************************************************************)
(*                                                                           *)
(*                              User Expressions                             *)
(*                                                                           *)
(*****************************************************************************)

open Fmt
open Base
open Pd     
open Suite

(*****************************************************************************)
(*                              Type Definitions                             *)
(*****************************************************************************)

type lvl = int
type idx = int
type mvar = int
type name = string

type icit =
  | Impl
  | Expl

type 'a tele = (name * icit * 'a) suite

type quot_cmd =
  | PComp of unit pd 
  | SComp of int list
        
type expr =
  | VarE of name
  | LamE of name * icit * expr
  | AppE of expr * expr * icit
  | PiE of name * icit * expr * expr
  | QuotE of quot_cmd
  | ObjE of expr
  | HomE of expr * expr * expr
  | CohE of expr tele * expr
  | CylE of expr * expr * expr
  | BaseE of expr
  | LidE of expr
  | CoreE of expr 
  | ArrE of expr
  | CatE
  | TypE
  | HoleE

type defn =
  | TermDef of name * expr tele * expr * expr
  | CohDef of name * expr tele * expr

(*****************************************************************************)
(*                Generic Pasting Diagram to Telescope Routine               *)
(*****************************************************************************)

module type TeleGen = sig
  
  type s
  type l 
  
  val lift : int -> s -> s
  val cat : s
  val obj : s -> s
  val hom : s -> s -> s -> s
  val nm : l -> lvl -> string
  val var : l -> lvl -> s
  val base_cat : s
    
end

module PdToTele(G : TeleGen) = struct
  open G

  let rec pd_to_tele_br tl cat src tgt k br =
    match br with
    | Br (l,brs) ->
      let cat' = hom cat src tgt in
      let ict = if (Suite.is_empty brs) then Expl else Impl in
      let ntl = Ext (tl,(nm l k,ict,obj cat')) in
      let (tl',_,k') = pd_to_tele_brs ntl
          (lift 1 cat') (var l k)
          (k+1) brs in
      (tl' , lift (k'-k) tgt, k')

  and pd_to_tele_brs tl cat src k brs =
    match brs with
    | Emp -> (tl, src, k)
    | Ext (brs',(l,br)) ->
      let (tl',src',k') = pd_to_tele_brs tl cat src k brs' in
      let cat' = lift (k'-k) cat in
      let v' = var l k' in
      let ntl = Ext (tl',(nm l k',Impl,obj cat')) in
      pd_to_tele_br ntl
        (lift 1 cat')
        (lift 1 src') 
        v' (k'+1) br

  let pd_to_tele pd =
    match pd with
    | Br (l,brs) ->
      let ict = if (Suite.is_empty brs) then Expl else Impl in
      let (tl,_,_) = pd_to_tele_brs
          (Emp |> ("C",Impl,cat) |> (nm l 1, ict, obj base_cat))
          (lift 1 base_cat) (var l 1) 2 brs in tl
  
end

let pd_to_expr_tele : string pd -> expr tele = fun pd ->
  let open PdToTele(struct
      type s = expr
      type l = string
      let lift _  t = t
      let cat = CatE
      let obj c = ObjE c
      let hom c s t = HomE (c,s,t)
      let nm l _ = l
      let var l _ = VarE l
      let base_cat = VarE "C" 
    end) in pd_to_tele pd 

(*****************************************************************************)
(*                        Expr Tele to Pasting Diagram                       *)
(*****************************************************************************)

let (let*) m f = Base.Result.bind m ~f 

let rec unhom e =
  match e with
  | HomE (c,_,_) ->
    let (cat,dim) = unhom c in
    (cat,dim+1)
  | _ -> (e, 0)

let unobj e =
  match e with
  | ObjE c -> Ok c
  | _ -> Error "not an object type"

let rec ith_tgt i ty tm =
  if (i = 0) then Ok (ty, tm) else
    match ty with
    | HomE (c,_,t) ->
      ith_tgt (i-1) c t
    | _ -> Error "No target"

let expr_tele_to_pd tl = 
  let rec go l tl =
    (* pr "Trying pasting context: @[<hov>%a@]@," (pp_suite pp_value) loc; *)
    match tl with
    | Emp -> Error "Empty context is not a pasting diagram"
    | Ext(Emp,_) -> Error "Singleton context is not a pasting diagram"
                      
    | Ext(Ext(Emp,(c,_,CatE)),(x,_,ObjE (VarE c'))) ->
      if (Poly.(<>) c c') then
        Error "Incorrect base category"
      else
        Ok (Pd.Br (x,Emp),VarE c,VarE x,2,0)
        
    | Ext(Ext(loc',(t,_,ObjE tty)),(f,_,ObjE fty)) -> 
      
      let* (pd,sty,stm,k,dim) = go (l+2) loc' in
      let (_,tdim) = unhom tty in
      let codim = dim - tdim in
      let* (sty',stm') = ith_tgt codim sty stm in 
      
      if (Poly.(<>) sty' tty) then
        Error "incompatible source and target types"
      else let ety = HomE (sty',stm',VarE t) in
        if (Poly.(<>) ety fty) then 
          Error "incorrect filling type"
        else let* pd' = Pd.insert_right pd tdim t
                 (Pd.Br (f, Emp)) in
          Ok (pd', fty, VarE f, k+2, tdim+1)
        
    | _ -> Error "malformed pasting context"
             
  in go 0 tl

(*****************************************************************************)
(*                       Unbiased Composite Generation                       *)
(*****************************************************************************)

let rec app_suite v s =
  match s with
  | Emp -> v
  | Ext (s',(ict,u)) -> AppE (app_suite v s', u, ict)

let pd_args cat pd =
  let open Pd in
  
  let rec pd_args_br args br =
    match br with
    | Br (v,brs) ->
      let ict = if (is_empty brs) then Expl else Impl in
      pd_args_brs (Ext (args,(ict,v))) brs

  and pd_args_brs args brs =
    match brs with
    | Emp -> args
    | Ext (brs',(v,br)) ->
      let args' = pd_args_brs args brs' in
      pd_args_br (Ext (args',(Impl,v))) br 

  in pd_args_br (Ext (Emp,(Impl,cat))) pd 
    
let unbiased_comp pd = 
  let open Pd in

  let with_vars pd = pd_lvl_map pd (fun l -> str "x%d" l) in
  
  let rec build_type cohs bdy cat =
    match (cohs , bdy) with
    | (Emp, Emp) -> cat
    | (Ext (c',coh_opt), Ext (b',(s,t))) ->
      let c = build_type c' b' cat in
      let src_args = pd_args cat s in
      let tgt_args = pd_args cat t in 
      (match coh_opt with
       | None -> HomE (c, snd (head src_args), snd (head tgt_args))
       | Some (g,a) ->
         let src = app_suite (CohE (g,a)) src_args in
         let tgt = app_suite (CohE (g,a)) tgt_args in
         HomE (c, src, tgt)
      )
    | _ -> raise (Failure "length mismatch")

  in 

  let rec go pd d =
    if (is_disc pd) then
      repeat (d+1) None
    else
      let src = truncate true (d-1) pd in
      let cohs = go (with_vars src) (d-1) in
      (* pr "About to handle: %a\n" pp_tr pd; *)
      let g = pd_to_expr_tele pd in
      (* pr "tele: %a\n" (pp_tele pp_term) g; *)
      let a = build_type cohs (boundary (map_pd pd ~f:(fun s -> VarE s))) (VarE "C") in
      (* pr "return type is: %a\n" pp_term a; *)
      Ext (cohs, Some (g,a))
        
  in let pdv = with_vars pd 
  in match go pdv (dim_pd pd) with
  | Emp -> VarE (head (labels pdv))
  | Ext (_,None) -> VarE (head (labels pdv))
  | Ext (_,Some (g,a)) -> CohE (g,a)

(*****************************************************************************)
(*                         Pretty Printing Raw Syntax                        *)
(*****************************************************************************)
           
let is_app e =
  match e with
  | AppE (_, _, _) -> true
  | _ -> false

let is_pi e =
  match e with
  | PiE (_,_,_,_) -> true
  | _ -> false

let pp_tele pp_el ppf tl =
  let pp_trpl ppf (nm,ict,t) =
    match ict with
    | Expl -> pf ppf "(%s : %a)" nm pp_el t
    | Impl -> pf ppf "{%s : %a}" nm pp_el t
  in pp_suite pp_trpl ppf tl 

let pp_quot_cmd ppf c =
  match c with
  | PComp pd ->
    pf ppf "pcomp %a" pp_tr pd 
  | SComp ds ->
    pf ppf "scomp %a" (list ~sep:(any " ") int) ds 

let rec pp_expr_gen show_imp ppf expr =
  let ppe = pp_expr_gen show_imp in 
  match expr with
  | VarE nm -> string ppf nm
  | LamE (nm,Impl,bdy) -> pf ppf "\\{%s}. %a" nm ppe bdy
  | LamE (nm,Expl,bdy) -> pf ppf "\\%s. %a" nm ppe bdy
  | AppE (u, v, Impl) ->
    if show_imp then 
      pf ppf "%a {%a}" ppe u ppe v
    else
      pf ppf "%a" ppe u 
  | AppE (u, v, Expl) ->
    let pp_v = if (is_app v) then
        parens ppe
      else ppe in 
    pf ppf "%a %a" ppe u pp_v v
  | PiE (nm,Impl,dom,cod) ->
    pf ppf "{%s : %a} -> %a" nm
      ppe dom ppe cod
  | PiE (nm,Expl,a,b) when Poly.(=) nm "" ->
    let pp_a = if (is_pi a) then
        parens ppe
      else ppe in 
    pf ppf "%a -> %a" 
      pp_a a ppe b
  | PiE (nm,Expl,dom,cod) ->
    pf ppf "(%s : %a) -> %a" nm
      ppe dom ppe cod
  | QuotE c -> pf ppf "`[ %a ]" pp_quot_cmd c
  | ObjE e -> pf ppf "[%a]" ppe e
  | HomE (c,s,t) ->
    pf ppf "%a | %a => %a" ppe c ppe s ppe t
    (* pf ppf "%a => %a" ppe s ppe t *)
  | CohE (g,a) ->
    (* (match expr_tele_to_pd g with
     *  | Ok (pd,_,_,_,_) ->
     *    pf ppf "@[<hov>@[<hov>coh [ %a : @]@[<hov>%a ]@]@]"
     *      (pp_pd string) pd ppe a
     *  | Error _ -> 
     *    pf ppf "coh [ %a : %a ]" (pp_tele ppe) g ppe a) *)
    
    pf ppf "coh [ %a : %a ]" (pp_tele ppe) g ppe a
    
   | CylE (b,l,c) ->
    pf ppf "[| %a | %a | %a |]" ppe b ppe l ppe c 
  | BaseE c ->
    pf ppf "base %a" ppe c
  | LidE c ->
    pf ppf "lid %a" ppe c
  | CoreE c ->
    pf ppf "core %a" ppe c 
  | ArrE c ->
    pf ppf "Arr %a" ppe c
  | CatE -> string ppf "Cat"
  | TypE -> string ppf "U"
  | HoleE -> string ppf "_"

let pp_expr = pp_expr_gen false
let pp_expr_with_impl = pp_expr_gen true
