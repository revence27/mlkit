
(* At some point we should clean up this code.. Constructors are not
 * looked up in the environment anymore.. Also, - it would be nice if
 * primitives were declared in the initial environment (this makes the
 * prelude smaller and better code is generated when compiling
 * multible compilation units (inlining of primitives will happen
 * automatically)). (martin) *)

functor CompileDec(structure Con: CON   
                   structure Excon: EXCON
                   structure TyName: TYNAME
                   structure Lvars: LVARS

		   structure TopdecGrammar: TOPDEC_GRAMMAR

                   structure StatObject : STATOBJECT
                     sharing type StatObject.TyName = TyName.TyName

 		   structure Environments : ENVIRONMENTS
		     sharing type Environments.TypeFcn = StatObject.TypeFcn
		         and type Environments.TypeScheme = StatObject.TypeScheme
		         and type Environments.Type = StatObject.Type
			 and type Environments.TyVar = StatObject.TyVar
			 and type Environments.id = TopdecGrammar.id
			 and type Environments.strid = TopdecGrammar.strid
			 and Environments.TyName = TyName

                   structure LambdaExp: LAMBDA_EXP
                     sharing type LambdaExp.lvar = Lvars.lvar
                         and type LambdaExp.con = Con.con
                         and type LambdaExp.excon = Excon.excon
                         and type LambdaExp.TyName = TyName.TyName

		   structure LambdaBasics : LAMBDA_BASICS
		     sharing type LambdaBasics.LambdaExp = LambdaExp.LambdaExp
		         and type LambdaBasics.excon = LambdaExp.excon
			 and type LambdaBasics.lvar = LambdaExp.lvar
			 and type LambdaBasics.subst = LambdaBasics.subst
			 and type LambdaBasics.tyvar = LambdaExp.tyvar
			 and type LambdaBasics.Type = LambdaExp.Type

                   structure CompilerEnv: COMPILER_ENV
                     sharing type CompilerEnv.con = Con.con
                         and type CompilerEnv.excon = Excon.excon
                         and type CompilerEnv.lvar = Lvars.lvar
                         and type CompilerEnv.Type = LambdaExp.Type
			 and type CompilerEnv.tyvar = LambdaExp.tyvar
			 and type CompilerEnv.id = TopdecGrammar.id
			 and type CompilerEnv.longid = TopdecGrammar.DecGrammar.longid
			 and type CompilerEnv.TypeScheme = StatObject.TypeScheme
			 and type CompilerEnv.strid = TopdecGrammar.strid
			 and type CompilerEnv.longstrid = TopdecGrammar.longstrid
			 and type CompilerEnv.ElabEnv = Environments.Env
			 and type CompilerEnv.TyName = TyName.TyName
			 and type CompilerEnv.tycon = Environments.tycon
			 and type CompilerEnv.longtycon = TopdecGrammar.longtycon

		   structure ElabInfo : ELAB_INFO
                     sharing type ElabInfo.ElabInfo = TopdecGrammar.info
                         and type ElabInfo.TypeInfo.longid = TopdecGrammar.DecGrammar.longid
                         and type ElabInfo.TypeInfo.TyEnv = Environments.TyEnv
                         and type ElabInfo.TypeInfo.TyVar = StatObject.TyVar
		         and type ElabInfo.TypeInfo.Type = StatObject.Type
		         and type ElabInfo.TypeInfo.Env = Environments.Env
			 and type ElabInfo.TypeInfo.strid = TopdecGrammar.strid
			 and type ElabInfo.TypeInfo.tycon = TopdecGrammar.tycon = CompilerEnv.tycon
			 and type ElabInfo.TypeInfo.id = TopdecGrammar.id

                   structure FinMap: FINMAP

	           structure FinMapEq: FINMAPEQ

                   structure Flags : FLAGS
                   structure PrettyPrint : PRETTYPRINT
                     sharing type PrettyPrint.StringTree = CompilerEnv.StringTree
		       = LambdaExp.StringTree = ElabInfo.StringTree
                   structure Report : REPORT
		     sharing type Report.Report = Flags.Report
		       = PrettyPrint.Report
		       = ElabInfo.ParseInfo.SourceInfo.Report
                   structure Crash: CRASH

                  ): COMPILE_DEC =
  struct

    structure Int = Edlib.Int
    structure List = Edlib.List
    structure ListSort = Edlib.ListSort
    structure ListPair = Edlib.ListPair
    structure EqSet = Edlib.EqSet

    open LambdaExp
    type function = {lvar : lvar, tyvars : tyvar list, Type : Type,
		     bind : LambdaExp}
    structure DecGrammar = TopdecGrammar.DecGrammar
    open DecGrammar

    (*import from StatObject:*)
    structure TyVar        = StatObject.TyVar            (* be careful - there are *)
         type TyVar        = StatObject.TyVar            (* two kinds of TyVar's around *)
    structure Type         = StatObject.Type
    structure TypeScheme   = StatObject.TypeScheme
    structure TypeFcn      = StatObject.TypeFcn

    (*import from Environments:*)
    type VarEnv            = Environments.VarEnv
    type TyEnv             = Environments.TyEnv
    type StrEnv            = Environments.StrEnv
    structure VE           = Environments.VE
    structure TyStr        = Environments.TyStr
    structure TE           = Environments.TE
    structure SE           = Environments.SE

    (*import from otherwhere:*)
    structure OverloadingInfo = ElabInfo.OverloadingInfo
    structure TypeInfo = ElabInfo.TypeInfo
    structure CE = CompilerEnv
         type CEnv = CE.CEnv
    structure TLE = LambdaExp

    infix plus
    val (op plus) = CE.plus

    fun die s = Crash.impossible ("CompileDec." ^ s)
    fun pr (s : string) : unit = TextIO.output(TextIO.stdOut, s)

    val region_profiling = Flags.lookup_flag_entry "region_profiling"

    val line = Report.line
    val // = Report.//
    infix //
    val report_SourceInfo =
            ElabInfo.ParseInfo.SourceInfo.report
	  o ElabInfo.ParseInfo.to_SourceInfo
	  o ElabInfo.to_ParseInfo

    (* ----------------------------------------
     * Environment functions
     * ---------------------------------------- *)

    fun declareExcon(id,(excon,tau),CE) = CE.declareExcon(id,(excon,tau),CE)
    fun declareCon(id,(con,tyvars,tau,it),CE) = CE.declareCon(id,(con,tyvars,tau,it),CE)

    datatype lookup_info = NORMAL of ElabInfo.ElabInfo | OTHER of string
    fun lookup_error(kind: string, CE, longid, info:lookup_info) =
            let fun say s = ((*TextIO.output(TextIO.stdOut, s );*)
                             TextIO.output(!Flags.log, s);
                             TextIO.flushOut(!Flags.log))
                fun sayst(st) = PrettyPrint.outputTree(say, st, !Flags.colwidth)
                fun say_compilerenv() = sayst(CE.layoutCEnv CE)
                fun say_info(NORMAL i) = sayst(ElabInfo.layout i)
                  | say_info(OTHER  s) = say s
            in
                say "\n.............";
                say_info(info);
                say ("Cannot find " ^ kind ^ " " ^  Ident.pr_longid longid
                     ^" in compiler environment:\n");
                say_compilerenv();
                die "lookup_error"
            end

    fun lookupLongexcon CE longid (info:lookup_info)= 
      case CE.lookup_longid CE longid
	of SOME(CE.EXCON (excon,tau)) => (excon,tau)
         | _ => lookup_error("long exception constructor",CE,longid,info)

    fun lookupLongcon CE longid (info:lookup_info)=
      case CE.lookup_longid CE longid
	of SOME(CE.CON (con,_,_,_,_)) => con
	 | _ => lookup_error("long value constructor",CE,longid,info)

    fun lookupLongid CE longid (info:lookup_info) = 
         case CE.lookup_longid CE longid of
           SOME res => res
         | NONE  => lookup_error("long value variable",CE,longid,info)

    fun lookup_longstrid ce longstrid = CE.lookup_longstrid ce longstrid

    local 
      open TLE 
    in
      val TLEunit = PRIM(RECORDprim,[])

      fun monoLet((lv,tau,lamb1),lamb2) =
        LET{pat=[(lv,[],tau)],
            bind=lamb1,
            scope=lamb2}
    end

    fun new_lvar_from_string_opt NONE = Lvars.newLvar ()  
      | new_lvar_from_string_opt (SOME string) = Lvars.new_named_lvar string
    val new_lvar_from_id = Lvars.new_named_lvar o Ident.pr_id
    val new_lvar_from_pat =
          new_lvar_from_string_opt o DecGrammar.find_topmost_id_in_pat
    fun new_lvar_from_pats [pat] = new_lvar_from_pat pat
      | new_lvar_from_pats _ = Lvars.newLvar ()


    (* -----------------------------------------------------
     * Container for collecting data type bindings
     * ----------------------------------------------------- *)

	 
	 (*MEMO: clean up this text.. re plus_datbindss: the state
	  contains a list of lists of datbinds: one datbind list from
	  each datatype declaration.  When adding a datbind list to
	  this list of datbind lists, that datbind list is thinned out
	  removing all datbinds that define a tyname that is already
	  defined in the current state.  Why would the same tyname
	  occur twice?  Because of datatype replication:

	      datatype t = K of int
	      datatype s = datatype t

	  In this example, we only want a singleton datbind list list
	  (I think).  plus_datbindss is not associative.  Maybe that
	  is not a problem.  06/03/1997 14:49. tho.*)


    type datbind_list  = (TLE.tyvar list * TyName * (con * LambdaExp.Type option) list) list

    structure DatBinds : sig val add : datbind_list -> unit
			     val extract : unit -> datbind_list list
			     val reset : unit -> unit
			 end =
      struct
	val datbindss : datbind_list list ref = ref [] 
	fun add datbinds = datbindss := (datbinds :: (! datbindss))
	fun extract() = rev(!datbindss)
	fun reset() = datbindss := []
      end

    (* ----------------------------------------------
     * Compiling type variables
     * ---------------------------------------------- *)

   structure TV : sig val reset : unit -> unit
		      val lookup : string -> TyVar -> TLE.tyvar
		  end =
      struct
	val env : (TyVar, TLE.tyvar) FinMapEq.map ref = ref FinMapEq.empty
	fun look a = FinMapEq.lookup TyVar.eq a
	fun add a = FinMapEq.add TyVar.eq a
	fun lookup s tv =
	      (case look (!env) tv of
		 SOME tv' => tv'
	       | NONE => let val tv' = if TyVar.equality tv then TLE.fresh_eqtyvar()
				       else TLE.fresh_tyvar ()
			 in env := add(tv,tv',!env); tv'
			 end)
		 handle ? => (TextIO.output (TextIO.stdOut, "  [TV.lookup " ^ s ^ "]  ") ;
			      raise ?)

	fun reset() = env := FinMapEq.empty
      end


    (* ---------------------------------------------------------------------- *)
    (*                     Utilities                                          *)
    (* ---------------------------------------------------------------------- *)

    fun to_TypeInfo i =
      case ElabInfo.to_TypeInfo i
	of SOME ti => SOME(TypeInfo.normalise ti)
	 | NONE => NONE 

    fun makeList (f: 'a -> 'a option) (x: 'a) =
      x :: (case f x of SOME y => makeList f y
                      | NONE => nil)

    local 
      open TypeInfo
    in
      fun type_of_exp (exp: DecGrammar.exp) : StatObject.Type =
        case to_TypeInfo (get_info_exp exp) of 
          SOME(EXP_INFO{Type}) => Type
        | _ => die "type_of_exp"

      fun type_of_match (match: DecGrammar.match) : StatObject.Type =
        case to_TypeInfo (get_info_match match) of 
          SOME(MATCH_INFO{Type}) => Type
        | _ => die "type_of_match"
    end      

    fun map_opt f (SOME x) = SOME (f x)
      | map_opt f NONE = NONE

    fun app_opt f (SOME x) = (f x)
      | app_opt f NONE = ()

    fun NoSome errmsg x =
      case x of 
        NONE => die errmsg
      | SOME y => y

    fun zip3(hd :: tl, hd' :: tl', hd'' :: tl'') =
          (hd, hd', hd'') :: zip3(tl, tl', tl'')
      | zip3(nil, nil, nil) = nil
      | zip3 _ = die "zip3"

    local
      fun unzip3'((x, y, z) :: rest, xs, ys, zs) =
            unzip3'(rest, x :: xs, y :: ys, z :: zs)
        | unzip3'(nil, xs, ys, zs) = (xs, ys, zs)
    in
      fun unzip3 triples = unzip3'(rev triples, nil, nil, nil)
    end

    fun zip4(hd :: tl, hd' :: tl', hd'' :: tl'', hd''' :: tl''') =
          (hd, hd', hd'', hd''') :: zip4(tl, tl', tl'', tl''')
      | zip4(nil, nil, nil, nil) = nil
      | zip4 _ = die "zip4"

    fun mk_env declare (xs,ys) =
      List.foldR (fn (x,y) => fn env => declare(x,y,env))
                 CE.emptyCEnv
                 (ListPair.zip(xs,ys))

    fun mk_env' declare (xs,ys,zs) =
      List.foldR (fn (x,y,z) => fn env => declare(x,y,z,env))
      CE.emptyCEnv (zip3(xs,ys,zs))

    fun pr_list (pr: 'a -> string) (l : 'a list) : string =
      let fun pr_l [] = ""
	    | pr_l (a::b::rest) = pr a ^ "," ^ pr_l (b::rest)
	    | pr_l [a] = pr a
      in "[" ^ pr_l l ^ "]"
      end

    fun hd s (x::xs) = x
      | hd s [] = die (s ^ ".hd")



    (* ---------------------------------------------------------------------- *)
    (*           Utility functions used to compile constructors               *)
    (* ---------------------------------------------------------------------- *)

    fun compileExCon (id:id) : excon = Excon.mk_excon(Ident.pr_id id)

    fun compileCon (id:id) : con = Con.mk_con(Ident.pr_id id)


    (* ---------------------------------------------------------------------- *)
    (*         Compilation of the semantic objects Type and TypeScheme        *)
    (* ---------------------------------------------------------------------- *)

    (* compileTyName is necessary because char, word8, and word from
     * CompileDec onwards are treated as int. I think we should
     * eventually support all base types in the backend (the fact that
     * there is not a one-to-one correspondence between type names
     * here and for elaboration makes me uneasy - Martin *)

    fun compileTyName tyname =
          if TyName.eq (tyname, TyName.tyName_CHAR)
	  orelse TyName.eq (tyname, TyName.tyName_WORD) 
	  orelse TyName.eq (tyname, TyName.tyName_WORD8) 
	  then TyName.tyName_INT
	  else tyname

    fun compileType (typ: StatObject.Type) : LambdaExp.Type =
        case Type.to_RecType typ of
          NONE =>
            (case Type.to_ConsType typ of 
               NONE => 
                 (case Type.to_FunType typ of 
                    NONE => 
                      (case Type.to_TyVar typ of
                         NONE => die "compileType(1)"
                       | SOME tyvar => TYVARtype(TV.lookup "compileType" tyvar))
                  | SOME funtype => 
                      let val (ty1,ty2) = NoSome "compileType(2)" 
                                        (Type.un_FunType funtype)
			  val ty1' = compileType ty1
			  val ty2' = compileType ty2
                      in ARROWtype([ty1'],[ty2'])
                      end)
             | SOME constype =>
                 let val (tys,tyname) = NoSome "compileType(3)" 
		                        (Type.un_ConsType constype)
		     val tys' = map compileType tys
                 in CONStype(tys', compileTyName tyname)
                 end)
        | SOME rho =>
            let val labtys = Type.RecType.to_list rho
	        val tys' = map (compileType o #2) labtys
            in RECORDtype tys'
            end

      val compileType = fn typ =>
        (if !Flags.DEBUG_COMPILER andalso false then 
           TextIO.output(TextIO.stdOut,"compileType: typ = " ^ Type.string typ ^ "\n")
         else ();
         compileType typ)

      val domType : StatObject.Type -> StatObject.Type =
        #1 o (NoSome "domType(2)") o Type.un_FunType  
        o (NoSome "domType(1)") o Type.to_FunType

      fun compileTypeScheme (tyvars : TyVar list, Type : StatObject.Type)
                  : (TLE.tyvar list * TLE.Type)  =
          let val tvs' = map (TV.lookup "compileTypeScheme") tyvars
	      val tau' = compileType Type
	  in (tvs', tau')
	  end

      fun compileTyVar tyvar : TLE.tyvar = TV.lookup "compileTyVar" tyvar


    (* ---------------------------------------------------------------------- *)
    (*	       Compilation and normalization of constructor bindings          *)
    (* ---------------------------------------------------------------------- *)

    (* We normalize constructor bindings such that if
     *
     *      CE =  {A |-> \/ab.a -> (a,b) t,
     *             B |-> \/ba.a -> (b,a) t}
     * we get:
     *
     *      CE' = {A |-> \/ab.a -> (a,b) t,
     *             B |-> \/ab.b -> (a,b) t}
     * or:
     *
     *      ([a,b], t, [(A, SOME a), (B, SOME b)])
     *)

   fun on_TypeOpt _ NONE = NONE
     | on_TypeOpt S (SOME tau) = SOME (LambdaBasics.on_Type S tau)

   fun unTyVarType (TYVARtype tv) = tv
     | unTyVarType _ = die "unTyVarType"

   (* normalize_sigma tyvars0 Type:
      Type is the body of a type scheme of a constructor; 
      tyvars0 are the bound variables
      of the type scheme. 
      normalize_sigma tyvars0 Type normalizes Type into
      a type where the type arguments come in the same order
      as tyvars0
    *)

   fun normalize_sigma' (tyvars0: TLE.tyvar list, Type: Type)
	 : TLE.tyvar list * TLE.tyvar list * Type * Type option=
     let
       val (tyvars, tauOpt, tyname) =
	 case Type 
	   of ARROWtype([tau],[CONStype(taus,tyname)]) => (map unTyVarType taus, SOME tau, tyname)
	    | CONStype(taus,tyname) => (map unTyVarType taus, NONE, tyname)
	    | _ => die "normalize_sigma': wrong type"
       val S = LambdaBasics.mk_subst (fn () => "CompileDec.normalize_sigma'")
	         (tyvars, map TLE.TYVARtype tyvars0) 
       val tauOpt' = on_TypeOpt S tauOpt
       val tau = case tauOpt'
		   of SOME tau => ARROWtype([tau],[CONStype(map TYVARtype tyvars0, tyname)])
		    | NONE => CONStype(map TYVARtype tyvars0, tyname)
     in
       (tyvars,tyvars0, tau, tauOpt')
     end 

   fun normalize_sigma (tyvars0: TLE.tyvar list, Type: Type): TLE.tyvar list * Type=
     let val (_, tyvars0,tau', _) =  normalize_sigma' (tyvars0: TLE.tyvar list, Type: Type)
     in (tyvars0,tau') (* the normalized type scheme *)
     end

   fun compile_and_normalize_cb tyvars0 (con, Type) (env, cons_TypeOpts) 
     : CE.CEnv * (con * Type option) list =
     let val con' = compileCon con
       val (tyvars,_, tau, tauOpt') = normalize_sigma'(tyvars0, Type)
       val it : CE.instance_transformer = CE.mk_it tyvars tyvars0
     in
       (declareCon(con,(con',tyvars0,tau, it),env), (con', tauOpt') :: cons_TypeOpts)
     end

    (* ---------------------------------------------------------------------- *)
    (*	       Compilation of the semantic object (tyname, VE)                *)
    (*	       (i.e., almost a TyStr)                                         *)
    (* ---------------------------------------------------------------------- *)

   fun compile'TyStr' (tyname : TyName, VE : VarEnv) 
	 : CE.CEnv * TLE.tyvar list * (con * Type option) list =
      let
	val tyvars : TyVar list = 
	  let exception H of TyVar list
	  in (VE.CEfold (fn typescheme => fn cbs =>
			  let val (tyvars, _) = TypeScheme.to_TyVars_and_Type typescheme
			  in raise H tyvars
			  end) [] VE) handle H tyvars => tyvars
	  end
	val tyvars' = map (TV.lookup "compile'TyStr'") tyvars
	val cbs : (id * Type) list = 
	  VE.CEFold (fn (con, typescheme) => fn cbs =>
		      let val (_, tau) = TypeScheme.to_TyVars_and_Type typescheme
			  val tau' = compileType tau
		      in (con, tau') :: cbs
		      end) [] VE 
	val (env, cons_TypeOpts) =
	  List.foldL (compile_and_normalize_cb tyvars') (CE.emptyCEnv,[]) (rev cbs)
      in
	(env, tyvars', cons_TypeOpts)
      end



(* ---------------------------------------------------------------------- *)
(*         Pattern match compilation                                      *)
(* ---------------------------------------------------------------------- *)

local

(*The algorithm used in this pattern match compiler is described in
 PETER SESTOFT: ML pattern match compilation and partial evaluation.  In DANVY,
 GL�CK & THIEMANN (eds): Dagstuhl Seminar on Partial Evaluation (= Lecture
 Notes in Computer Science (no.?)) 1996.

 Consider this example input sml program to the kit

	    datatype t = A | B
	    fun f (A, A, _, _) = "0"
	      | f (_, _, A, A) = "1"
	      | f (A, B, A, B) = "last"

 Here is the unoptimised output from the pattern match compiler.  Every right
 hand side only appears once.  "1" has become a function, because two cases
 lead to "1".  The other nodes in the decdag ("rhs" nodes and "ifeq" nodes)
 have been inlined by the pattern match compiler, because it knew that they
 would only be jumped to from one place (i.e., the degree of those nodes in
 the decdag was 1).  "Fail" nodes are always inlined.

Report: UnOpt: 

   [...]

   (fn <x>=> 
    fix rhs1 = (fn <obj>=> "1")
    in  (case #0 x  of 
           A => 
           (case #1 x  of 
              A => "0"
            | _ => 
              (case #2 x  of 
                 A => (case #3 x  of A => rhs1 () | _ => "last")
               | _ => raisePRIM(Match, []),Types(<string>)))
         | _ => 
           (case #2 x  of 
              A => 
              (case #3 x  of A => rhs1 () | _ => raisePRIM(Match, []),Types(<string>))
            | _ => raisePRIM(Match, []),Types(<string>)))
    end)

 Naturally, the optimiser inlines the very small function body "1":

Report: Opt: 

  [...]

   (fn <x'>=> 
    (case #0 x'  of 
       A => 
       (case #1 x'  of 
          A => "0"
        | _ => 
          (case #2 x'  of 
             A => (case #3 x'  of A => "1" | _ => "last")
           | _ => raisePRIM(Match, []),Types(<string>)))
     | _ => 
       (case #2 x'  of 
          A => (case #3 x'  of A => "1" | _ => raisePRIM(Match, []),Types(<string>))
          | _ => raisePRIM(Match, []),Types(<string>)))) 

 If we make the pattern bigger, there will be more nodes in the decdag that
 have more than one in-edge, & thus there will be more functions in the fix
 created by the pattern matcher:

	  fun f (A, A, _, _, _, _) = "0"
	    | f (_, _, A, A, _, _) = "1"
	    | f (_, _, _, _, A, A) = "2"
	    | f (A, B, A, B, A, B) = "last"

Report: UnOpt: 

 (fn <y>=> 
  fix n5_A? =
        (fn <obj>=> 
          (case #4 y of 
             A => (case #5 y of A => rhs2 () | _ => raisePRIM(Match, []),Types(<string>))
           | _ => raisePRIM(Match, []),Types(<string>))), 
      rhs2 = (fn <obj>=> "2"), 
      rhs1 = (fn <obj>=> "1")
  in  (case #0 y of 
         A => 
         (case #1 y of 
            A => "0"
          | _ => 
            (case #2 y of 
               A => 
               (case #3 y of 
                  A => rhs1 ()
                | _ => 
                  (case #4 y of 
                     A => (case #5 y of A => rhs2 () | _ => "last")
                   | _ => raisePRIM(Match, []),Types(<string>)))
             | _ => n5_A? ()))
       | _ => 
         (case #2 y of 
            A => (case #3 y of A => rhs1 () | _ => n5_A? ())
          | _ => n5_A? ()))
  end)

Report: Opt: 

 (fn <y'>=> 
  fix n5_A? = 
         (fn <obj>=> 
          (case #4 y'  of 
             A => (case #5 y' of A => "2" | _ => raisePRIM(Match, []),Types(<string>))
           | _ => raisePRIM(Match, []),Types(<string>)))
  in  (case #0 y' of 
         A => 
         (case #1 y' of 
            A => "0"
          | _ => 
            (case #2 y' of 
               A => 
               (case #3 y' of 
                  A => "1"
                | _ => 
                  (case #4 y' of 
                     A => (case #5 y' of A => "2" | _ => "last")
                   | _ => raisePRIM(Match, []),Types(<string>)))
             | _ => n5_A? ()))
       | _ => 
         (case 
            #2 y' of 
            A => (case #3 y' of A => "1" | _ => n5_A? ()) | _ => n5_A? ()))
  end)
 *)

  abstype span = Infinite | Finite of int
  with
    val span_from_int = Finite
    val span_infinite = Infinite
    val span_256 = Finite 256
    val span_1 = Finite 1
    fun span_eq Infinite Infinite = true
      | span_eq (Finite i1) (Finite i2) = i1 = i2
      | span_eq _ _ = false
    fun span_eq_int Infinite i = false
      | span_eq_int (Finite i1) i2 = i1 = i2
  end (*abstype*)

  datatype con = Con of {longid : longid,
			 span : span, 
			 nullary : bool,
			 info : ElabInfo.ElabInfo}
               | Scon of SCon.scon
	       | Excon of {longid : longid, nullary : bool}
               | Tuple of {arity : int}
  (*nullary=true when the (exception) constructor takes zero arguments;
   otherwise it takes one argument.*)
  
  fun string_from_con0 (Con {longid, ...}) = "Con {" ^ Ident.pr_longid longid ^ ", ...}"
    | string_from_con0 (Scon scon) = "Scon " ^ SCon.pr_scon scon
    | string_from_con0 (Excon {longid, ...}) = "Excon {" ^ Ident.pr_longid longid ^ ", ...}"
    | string_from_con0 (Tuple {arity}) = "Tuple {" ^ Int.string arity ^ "}"

  (*the type cmp, and the _cmp functions scattered around are used to define
   function ifeq_cmp which is used to define an orderfinmap that keeps track
   of what IfEq nodes have been created.  This is necessary because we want
   to build a dag, not a tree.*)

  datatype cmp = Lt | Gt | Eq

  fun cmp_from_lt lt (x1, x2) = if lt (x1, x2) then Lt
				else if lt (x2, x1) then Gt else Eq
  fun eq_from_cmp x_cmp (x1, x2) = (case x_cmp (x1, x2) of Eq => true | _ => false) 
  fun lt_from_cmp x_cmp (x1, x2) = (case x_cmp (x1, x2) of
				      Lt => true
				    | Gt => false
				    | Eq => false)

  val int_cmp = cmp_from_lt (op < : int * int -> bool)
  val lvar_cmp = cmp_from_lt Lvars.lt
  val scon_cmp = cmp_from_lt SCon.lt
  (*of course, longid_cmp ought to be in IDENT.sml & this is hacky, but then
  I would have to define datatype cmp somewhere else:*)
  fun longid_lt (longid1, longid2) =
	Ident.pr_longid longid1 < Ident.pr_longid longid2
  val longid_cmp = cmp_from_lt longid_lt

  fun con_ord (Con _) = 0
    | con_ord (Scon _) = 1
    | con_ord (Excon _) = 2
    | con_ord (Tuple _) = 3
  fun con_cmp (Con {longid=longid1, span=span1, nullary=nullary1, ...},
	       Con {longid=longid2, span=span2, nullary=nullary2, ...}) =
	longid_cmp (longid1, longid2) (*I think it must suffice to compare the longids?*)
    | con_cmp (Scon scon1, Scon scon2) = scon_cmp (scon1, scon2)
    | con_cmp (Tuple {arity=arity1}, Tuple {arity=arity2}) = int_cmp (arity1, arity2)
    | con_cmp (Excon {longid=longid1, ...}, Excon {longid=longid2, ...}) =
	longid_cmp (longid1, longid2)
    | con_cmp (con1, con2) = int_cmp (con_ord con1, con_ord con2)

  val con_eq = eq_from_cmp con_cmp

  fun arity (Con {nullary, ...}) = if nullary then 0 else 1
    | arity (Scon scon) = 0
    | arity (Excon {nullary, ...}) = if nullary then 0 else 1
    | arity (Tuple {arity}) = arity

  fun span (Con {span, ...}) = span
    | span (Scon (SCon.INTEGER x)) = span_infinite
    | span (Scon (SCon.STRING x)) = span_infinite
    | span (Scon (SCon.REAL x)) = die "span: real scon in pattern"
    | span (Scon (SCon.CHAR x)) = span_256
    | span (Scon (SCon.WORD x)) = span_infinite
    | span (Excon _) = span_infinite
    | span (Tuple {arity}) = span_1

  datatype path = Access of int * con * path | Obj
    (*a path is a description of how to access a component value of the value
     that is being pattern matched.  For instance, if the value being matched
     against is `(0, Bah (0,1,v,4))', the path

        Access (2, Tuple foo,
	        Access (0, Con {longid=Bah, ...},
		        Access (1, Tuple hoo,
			        Obj)))

     points out v, i.e., the first element in the path is the "innermost"
     part of the path.*)
    
  fun string_from_path (Access (i, con, path)) =
	"Access ("
	^ Int.string i ^ ", "
	^ string_from_con0 con ^ ", "
	^ string_from_path path ^ ")"
    | string_from_path Obj = "Obj"

  fun path_cmp (Obj, Obj) = Eq
    | path_cmp (Obj, Access _) = Lt
    | path_cmp (Access _, Obj) = Gt
    | path_cmp (Access (i1, pcon1, path1), Access (i2, pcon2, path2)) =
	(case int_cmp (i1, i2) of
	   Eq => (case con_cmp (pcon1, pcon2) of
		    Eq => path_cmp (path1, path2)
		  | cmp => cmp)
	 | cmp => cmp)

  val path_eq = eq_from_cmp path_cmp

  type declaration_to_be_made = id * (lvar * LambdaExp.tyvar list * Type) * path
  type declarations_to_be_made = declaration_to_be_made list
  type rhs = int
  type rhs' = declarations_to_be_made * rhs
  (*TODO 03/12/1997 19:36. tho.   kommenter rhs-typen.
   kommenter forskelle & ligheder med sestofts artikel.*)

  val string_from_rhs = Int.string
  fun string_from_rhs' (_, rhs) = string_from_rhs rhs

  structure conset : KIT_MONO_SET = OrderSet
    (structure Order : ORDERING = struct
       type T = con
       fun lt con1 con2 = lt_from_cmp con_cmp (con1, con2)
     end (*structure Order*)
     structure PP = PrettyPrint)

  structure negset = struct
    type negset = int (*number of cons in the set*) * conset.Set (*the cons*)
    val empty = (0, conset.empty)
    fun member con (i, conset) = conset.member con conset
    fun insert con (i, conset) = (i + 1, conset.insert con conset)
    fun size (i, _) = i
  end (*structure negset*)

       
  datatype termd = Pos of con * termd list | Neg of negset.negset
  type context = (con * termd list) list

  fun addneg (Neg negset, con) = Neg (negset.insert con negset)
    | addneg _ = die "addneg"

  fun augment ([], termd) = []
    | augment ((con, args) :: rest, termd)  = (con, termd :: args) :: rest

  fun norm ((con, args) :: rest) = augment (rest, Pos (con, rev args))
    | norm _ = die "norm" 

  fun buildtermd ([], termd, []) = termd
    | buildtermd ((con,args) :: rest, termd, (_, _, dargs) :: work) =
	buildtermd (rest, Pos (con, rev args @ (termd :: dargs)), work)
    | buildtermd _ = die "buildtermd"

  datatype matchresult = Yes | No | Maybe

  fun staticmatch (con : con, termd : termd) : matchresult =
	(case termd of
	   Pos (pcon, _) => (case con_cmp (con, pcon) of Eq => Yes | _ => No)
	 | Neg negset  => if negset.member con negset then No
			  else if span_eq_int (span con) (negset.size negset + 1)
			       then Yes
			       else Maybe)

  datatype kind = Success of rhs' | IfEq of ifeq
  withtype node = {lvar : lvar, kind : kind, refs : int ref, visited : bool ref}
       and edge = node option
       and ifeq = path * con * edge * edge

  type decdag = edge


  (*A  d e c i s i o n  d a g  is a dag (mas o menos) with edges of type t &
   nodes of type t'.  An edge either points to nothing (i. e., it is NONE :
   t) and means "fail", or it points to (is) a node & means "jump to that
   node".  A node is either a right hand side (of type rhs, i. e., a Success
   node) or a test with two branches, i.e., two edges (an IfEq node).  Each
   node will be compiled into a LambdaExp function.  (well, compile_match
   does that; compile_binding is a bit different).  The lvar of the node will
   be the name of that function and also serves as unique identification of
   the node.  Correspondingly, edges to nodes will be compiled to function
   calls.  Failure edges (i.e., NONE : t) will be compiled into "raise
   something".

   The "refs" field in a node is the number of edges to the node. When a node
   is created, it is set to 0, because we do not know at that point, whether
   anyone will ever jump to the node.  It is only when we make an edge to the
   node that we must bump this counter.

   Invariant: "visited" fields of all nodes are always false except within
   calls to reachable and compile_decdag.*)

  fun shared ({refs, ...} : node) = !refs > 1

  fun node_cmp ({lvar=lvar1, ...} : node, {lvar=lvar2, ...} : node) =
	lvar_cmp (lvar1, lvar2)
  fun opt_cmp x_cmp (NONE, NONE) = Eq
    | opt_cmp x_cmp (NONE, SOME _) = Lt
    | opt_cmp x_cmp (SOME _, NONE) = Gt
    | opt_cmp x_cmp (SOME x1, SOME x2) = x_cmp (x1, x2)
  val edge_cmp = opt_cmp node_cmp
  val edge_eq = eq_from_cmp edge_cmp

  fun ifeq_cmp ((path1 : path, con1 : con, then1 : edge, else1 : edge),
		(path2 : path, con2 : con, then2 : edge, else2 : edge)) =
	(case edge_cmp (else1, else2) of
	   Eq => (case edge_cmp (then1, then2) of
		    Eq => (case con_cmp (con1, con2) of
			     Eq => path_cmp (path1, path2)
			   | cmp => cmp)
		  | cmp => cmp)
	 | cmp => cmp)
					     
  local
    structure map = OrderFinMap
      (structure Order : ORDERING = struct
	 type T = ifeq
	 (*lt ifeq1 ifeq2 = lexicographic ordering of the components of the
	  tuples.  As long as it is a linear order, I can choose any
	  ordering, so I compare the components in an order such that in the
	  frequent cases it is determined as quickly as possible whether
	  ifeq1 < ifeq2.*)
	 fun lt ifeq1 ifeq2 = lt_from_cmp ifeq_cmp (ifeq1, ifeq2)
       end (*structure Order*)
       structure PP = PrettyPrint
       structure Report = Report)

    type mapr = node map.map ref
    val mapr : mapr = ref map.empty
    fun find_ifeq_node_like_this ifeq : node option = map.lookup (!mapr) ifeq
    val counter = ref 0
    fun next () = (counter := 1 + !counter ; !counter)
    fun string_from_con (Con {longid, ...}) = Ident.pr_longid longid
      | string_from_con (Scon (SCon.INTEGER i)) = Int.string i
      | string_from_con (Scon (SCon.STRING s)) = "a_string"
      | string_from_con (Scon (SCon.REAL r)) = "a_real"
      | string_from_con (Scon (SCon.CHAR c)) = "a_char"
      | string_from_con (Scon (SCon.WORD w)) = Int.string w
      | string_from_con (Excon {longid, ...}) = Ident.pr_longid longid
      | string_from_con (Tuple {arity}) = "a_tuple"

(*TODO 06/01/1998 10:55. tho.  kan man bruge indkanttallet ("refs") til
noget?  F. eks. til at se, om koden er d�d (fordi der er redundante regler)?
Problemet er, hvis der kan forekomme en ifeq-knude med indgrad 0.  S� er den
"d�d", & det er dens b�rn m�ske ogs�, men det kan man ikke se af deres
indkanttal, for det taltes op, da den "d�de" ifeq-knude blev skabt ...
Det finder du nok aldrig ud af.*)
	
  in
    val edge_bump = app_opt (fn {refs, ...} : node => refs := !refs + 1)

    fun mk_node kind s = {kind = kind, refs = ref 0, visited = ref false,
			  lvar = Lvars.new_named_lvar s}
    fun mk_ifeq_node (ifeq as (path, con, edge1, edge2)) : node =
	  let val node = mk_node (IfEq ifeq) ("n" ^ Int.string (next ())
					      ^ "_" ^ string_from_con con ^ "?")
	  in 
	    mapr := map.add (ifeq, node, !mapr) ;
	    edge_bump edge1 ;
	    edge_bump edge2 ;
	    node
	  end

    fun reset () = (mapr := map.empty ; counter := 0)
    fun ifeq_node ifeq : node =
	  (case find_ifeq_node_like_this ifeq of
	     SOME node => node
	   | NONE => mk_ifeq_node ifeq)

    val fail_edge = NONE
  end (*local*)


  type work = pat list * path list * termd list
  type rule = pat * node

  fun fail (termd : termd, []) = fail_edge
    | fail (termd, (pat1, rhs1) :: rulerest) =
	match_pat (pat1, Obj, termd, [], [], rhs1, rulerest)
  and succeed (ctx : context, [] : work list, rhs : node, rules : rule list) =
	SOME rhs
    | succeed (ctx, work1::workr, rhs, rules) =
	(case work1 of
	   ([],[],[]) => succeed (norm ctx, workr, rhs, rules)
	 | (pat1::patr, path1::pathr, termd1::termdr) =>
	     match_pat (pat1, path1, termd1, ctx,
			(patr, pathr, termdr)::workr, rhs, rules)
	 | _ => die "succeed")
  and match_pat (pat : pat, path : path, termd : termd, ctx : context,
		 work : work list, rhs : node, rules : rule list) =
	(case pat of
	   ATPATpat (info, atpat) => match_atpat (atpat, path, termd, ctx, work, rhs, rules)
	 | CONSpat (info, longid_op_opt, atpat) =>
	     (case to_TypeInfo info of
		SOME (TypeInfo.CON_INFO {numCons   : int,
					 index     : int,
					 instances : TypeInfo.Type list,
					 tyvars    : TyVar list,
					 Type      : TypeInfo.Type,
					 longid    : longid}) => 
		  match_con (Con {longid=longid, span=span_from_int numCons,
				  info=info,
		                  (*because it appears in a CONSpat:*)nullary=false})
		    [(0, ATPATpat (DecGrammar.bogus_info, atpat))]
		      (path, termd, ctx, work, rhs, rules)
	      | SOME (TypeInfo.EXCON_INFO {Type, longid}) =>
		  match_con (Excon {longid=longid,
				    (*because it appears in a CONSpat:*)nullary=false})
		    [(0, ATPATpat (DecGrammar.bogus_info, atpat))]
		      (path, termd, ctx, work, rhs, rules)
	       | _ => die "match_pat (CONSpat ...)")
	 | TYPEDpat (info, pat, ty) =>
	     match_pat (pat, path, termd, ctx, work, rhs, rules)
	 | LAYEREDpat (info, OP_OPT (id, _), ty_opt, pat) =>
	     match_pat (pat, path, termd, ctx, work, rhs, rules)
	 | UNRES_INFIXpat _ => die "match_pat (UNRES_INFIXpat ...)")
	
  and match_atpat (atpat, path, termd, ctx, work, rhs, rules) =
	(case atpat of
	   WILDCARDatpat info => succeed (augment (ctx, termd), work, rhs, rules)
	     (*WILDCARDatpat is treated almost like variable patterns*)
	 | SCONatpat (info, scon) =>
	     match_con (Scon scon) [] (path, termd, ctx, work, rhs, rules)
	 | LONGIDatpat (info, OP_OPT (longid, _)) =>
	     (case to_TypeInfo info of
		SOME (TypeInfo.VAR_PAT_INFO {tyvars, Type}) =>
		  (*it is a variable, not a nullary constructor*)
		  succeed (augment (ctx, termd), work, rhs, rules)
	      | SOME (TypeInfo.CON_INFO {numCons   : int,
					 index     : int,
					 instances : TypeInfo.Type list,
					 tyvars    : TyVar list,
					 Type      : TypeInfo.Type,
					 longid    : longid}) => 
		  match_con (Con {longid=longid, span=span_from_int numCons, info=info,
		                  (*because it appears in a LONGIDatpat:*)nullary=true})
		    [] (path, termd, ctx, work, rhs, rules)
	      | SOME (TypeInfo.EXCON_INFO {Type, longid}) =>
		  match_con (Excon {longid=longid,
				    (*because it appears in a LONGIDatpat:*)nullary=true})
		    [] (path, termd, ctx, work, rhs, rules)
	      | _ => die "match_atpat (LONGIDatpat ...)")
	 | RECORDatpat (info, patrow_opt) =>
	     let val patrows = (case patrow_opt of
		       NONE => []
		     | SOME patrow => makeList
			 (fn PATROW (_, _, _, patrow_opt) => patrow_opt
		           | DOTDOTDOT _ => die "match_atpat: DOTDOTDOT")
			 patrow)
	       val argpats =
		     map (fn PATROW (info, _, pat, _) =>
			  (case to_TypeInfo info of
			     SOME (TypeInfo.LAB_INFO {index, ...}) => (index, pat)
			   | _ => die "match_atpat: RECORDatpat info")
		           | _ => die "match_atpat: RECORDatpat patrow") patrows
	     in
	       match_con (Tuple {arity=List.size argpats}) argpats
	         (path, termd, ctx, work, rhs, rules)
	     end
	 | PARatpat (info, pat) => match_pat (pat, path, termd, ctx, work, rhs, rules))

  (*match_con pcon argpats (path, termd, ctx, work, rhs, rules) = `pcon' is
   the compile-time description of the constructor that we want to generate
   code to match.  `argpats' are the argument patterns to `pcon', each paired
   with its "Access number", the argument to the constructor Access that will
   access the component corresponding to that pattern.  The rest of the
   arguments of match_con describe the state of the pattern match compiler as
   they do in the other functions (`succeed', `match_pat' etc.).*)

  and match_con pcon (argpats : (int * pat) list)
	(path, termd, ctx, work, rhs, rules) =
	let
	  fun getdargs (Neg _) = map (fn _ => Neg negset.empty) argpats
	    | getdargs (Pos (con, dargs)) = dargs
	  fun getoargs () = map (fn (i, pat) => Access (i, pcon, path)) argpats
	  fun succeed' () = succeed
		((pcon, []) :: ctx,
		 (map #2 argpats, getoargs (), getdargs termd) :: work,
		 rhs,
		 rules)
	  fun fail' newtermd = fail (buildtermd (ctx, newtermd, work), rules)
	in
	  (case staticmatch (pcon, termd) of
	     Yes => succeed' ()
	   | No => fail' termd
	   | Maybe => let val left = succeed' ()
			  val right = fail' (addneg (termd, pcon))
		      in if edge_eq (left, right) then left
			 else SOME (ifeq_node (path, pcon, left, right)) 
		      end)
	end


  fun env_from (declarations_to_be_made : declarations_to_be_made) =
	List.foldL
	(*foldR could also have been used, as no id appears twice in
	 declarations_to_be_made because of syntactic restrictions enforced
	 by ElabDec*)
	  (fn (id, (lvar, tyvars, tau), path) => fn env_sofar =>
	   CE.declareVar (id, (lvar, tyvars, tau), env_sofar))
	  CE.emptyCEnv declarations_to_be_made


  fun compile_path env obj Obj = obj
    | compile_path env obj (Access (0, Con {info, ...}, path)) =
	(case to_TypeInfo info of
	   SOME (TypeInfo.CON_INFO {tyvars, Type, longid, instances, ...}) =>
	     (case lookupLongid env longid (NORMAL info) of
		CE.CON (con, tyvars, _, il, it) =>
		  let val instances' = map compileType instances
		      val S = CE.mk_subst (fn () => "CompileDec.compile_path")
				(tyvars, instances')
		      val il' = CE.apply_it (it, CE.on_il (S, il))
		  in
		    PRIM (DECONprim {con=con, instances=il'},
			  [compile_path env obj path])
		  end
	      | CE.REF =>
		  (case instances of [instance] =>
		       (*for deref, the instance is the instantiated argument type:*)
		       PRIM (DEREFprim {instance=CONStype ([compileType instance],
							   TyName.tyName_REF)},
			     [compile_path env obj path])
		   | _ => die "compile_path: ref instances")
	      | _ => die "compile_path: Con, longid")
	 | _ => die "compile_path: Con, info")
    | compile_path env obj (Access (_, Con _, path)) = die "compile_path: _, Con _"
    | compile_path env obj (Access (i, Excon {longid, ...}, path)) =
	PRIM (DEEXCONprim (#1 (lookupLongexcon env longid (OTHER "compile_path"))),
	      [compile_path env obj path])
    | compile_path env obj (Access (i, Tuple {arity}, path)) =
	if 0 <= i andalso i < arity
	then PRIM (SELECTprim i, [compile_path env obj path]) 
	else die "compile_path: i's range"
    | compile_path env obj (Access (_, Scon _, path)) = die "compile_path: scon"


  (*compile_rhs = TODO

   How? In

       fn ((42, (x, _)), (_, {y, ...})) => e1
        | ((_, (_, z)), (_, {y, ...})) => e2

   we will want to compile e1 to

      LET x = <code to access x>
      IN LET y = <code to access y>
      IN <e1 compiled in an environment that says something about x & y>

   The rhs for the first mrule will say something about x & y.  First, we use
   this information to build the abovementioned environment.  Then we compile
   e1 in it.  Then we add the surrounding LET's, again using the
   aforementioned information.*)

  fun compile_rhs' compile_no obj env rhs'  : LambdaExp =
	let
	  val (declarations_to_be_made : declarations_to_be_made, rhs) = rhs'
	  val env_rhs = CE.plus (env, env_from declarations_to_be_made)
	  val lexp = compile_no (rhs, env_rhs)
	in mk_declarations_to_be_made declarations_to_be_made lexp obj env 
	end

  and mk_declarations_to_be_made declarations_to_be_made lexp obj env
	: LambdaExp =
	List.foldL  (*again, foldR could also have been used*)
	  (fn (id, (lvar, tyvars, tau), path) => fn lexp_sofar =>
	   (LET {pat = [(lvar, tyvars, tau)],
		       bind = compile_path env obj path,
		       scope = lexp_sofar}))
		lexp declarations_to_be_made

in

  fun compile_jump_to ({lvar, ...} : node) =
	APP (VAR {lvar = lvar, instances = []}, PRIM (RECORDprim, []))
	  (*instances=[] because the var can never be polymorphic
	   because it is the name of a non-polymorphic function.*)

  fun switchify (path0, con0, edge1, edge2) =
	let fun switchify0 (s as (cases, SOME {kind=IfEq (path, con, edge1, edge2), refs, ...})) =
	          if path_eq (path0, path) andalso !refs <= 1
		  then switchify0 ((con, edge1) :: cases, edge2)
		  else s
	      | switchify0 s = s 
	in
	  switchify0 ([(con0, edge1)], edge2)
	end

  fun compile_node compile_no obj raise_something tau_return_opt env
	({visited, kind, ...} : node)    : function list * LambdaExp =
	(if !visited then die "compile_node: already visited" else () ;
	 visited := true ; 
	 (case kind of
	   IfEq (path, con, edge1, edge2) =>
	     let
	       val (cases, otherwise) = switchify (path, con, edge1, edge2)
	       fun switch (switch_x : 'x Switch -> LambdaExp,
			   compile_x : con -> 'x) : function list * LambdaExp =
		     (case
			List.foldL (fn (x, edge) => fn (functions, cases_compiled) =>
				    (case compile_edge compile_no obj raise_something
				            tau_return_opt env edge
				     of (functions', lexp') =>
				       (functions' @ functions,
					(compile_x x, lexp') :: cases_compiled)))
			  ([], []) cases
		      of (functions, cases_compiled) =>
		     (case compile_edge compile_no obj raise_something
			     tau_return_opt env otherwise
		      of (functions'', lexp_otherwise) =>
			(functions'' @ functions,
			 switch_x (SWITCH
				   (compile_path env obj path,
				    cases_compiled,
				    SOME (lexp_otherwise))))))
	     in
	       (case con of
		  Con _ => switch
		    (SWITCH_C,
		     fn Con {longid, ...} => lookupLongcon env longid
		                               (OTHER "compile_node, Con")
		      | _ => die "compile_node: fn Con =>")
		| Scon (SCon.INTEGER _) => switch
		    (SWITCH_I, fn Scon (SCon.INTEGER i) => i
		                | _ => die "compile_node: fn Scon (SCon.INTEGER i) =>")
		 | Scon (SCon.STRING _) => switch
		    (SWITCH_S, fn Scon (SCon.STRING s) => s
		                | _ => die "compile_node: fn Scon (SCon.STRING s) =>")
		 | Scon (SCon.REAL _) => die "compile_node: real"
		 | Scon (SCon.CHAR _) => switch
		    (SWITCH_I, fn Scon (SCon.CHAR i) => i
		                | _ => die "compile_node: fn Scon (SCon.CHAR i) =>")
		 | Scon (SCon.WORD _) => switch
		    (SWITCH_I, fn Scon (SCon.WORD i) => i
		                | _ => die "compile_node: fn Scon (SCon.WORD i) =>")
		 | Excon _ => switch
		    (SWITCH_E,
		     fn Excon {longid, ...} =>
			  #1 (lookupLongexcon env longid (OTHER "compile_node, Excon"))
		      | _ => die "compile_node: fn Excon {longid, ...} =>")
		 | Tuple _ => die "compile_node: Tuple")
	     end
	 | Success rhs' => ([], compile_rhs' compile_no obj env rhs')))

  and compile_edge  compile_no obj raise_something tau_return_opt env edge
	: function list * LambdaExp =
	(case edge of
	   NONE => ([], raise_something obj)
	 | SOME node =>
	     if shared node then
	       (if ! (#visited node) then [] else
		let val (functions, lexp) =
		  compile_node compile_no obj raise_something tau_return_opt env node
		    val Type = ARROWtype ([unitType],
					  [NoSome "compile_edge" tau_return_opt])
		    val function = {lvar= #lvar node, tyvars=[], Type=Type,
				    bind=FN {pat = [(Lvars.new_named_lvar "obj",
						     unitType)],
					     body = lexp}}
	             (*tyvars=[] because an rhs can never be polymorphic: FN
		      & HANDLE exps have no polymorphism, and
		      valbinds---which do have polymorphism---will always be
		      compiled to one big exp and no functions (see
		      compile_binding).*)
		in function :: functions
		end,
	        compile_jump_to node)
	     else compile_node compile_no obj raise_something tau_return_opt env node)

  val compile_decdag = compile_edge

  (*reachable edge = the nodes that are reachable from the edge `edge'; so
   `reachable decdag' gives you the nodes of the decdag `decdag'*)
 
  fun reachable (decdag : edge)   : node list =
	let val nodes = reachable0 decdag
	in List.apply (fn node => #visited node := false) nodes ;
	  nodes
	end

  (*invariant: visited fields of all nodes are always false except within
   calls to reachable*)

  and reachable0 NONE = []
    | reachable0 (SOME (node : node as {visited, ...})) =
	if !visited then [] else node :: visit_node node
  and visit_node node =
	(#visited node := true ; 
	 (case #kind node of
	    IfEq (path, con, edge1, edge2) => reachable0 edge1 @ reachable0 edge2
	  | Success rhs' => []))
		
  fun exhaustive (nodes : node list)  : bool =
	(*Presumably `nodes' is the complete list of nodes in some decdag.
	 The decdag is exhaustive if there is no failures in it, i.e., if all
	 edges go to some node, i.e., have the form `SOME _'*)
	not (List.exists (fn {kind=IfEq (path, pcon, NONE, _), ...} => true
                           | {kind=IfEq (path, pcon, _, NONE), ...} => true
			   | {kind=_, ...} => false)
	        nodes)

  (*redundant_rules nodes = a list of numbers of rhs's that will never be
   evaluated.  Presumably `nodes' is the complete list of nodes in some
   decdag.  In the case of

       fn (SOME _) => true | NONE => false | SOME x => x | _ => true

   you get the list [2,3] or [3,2], because the last two mrules are
   redundant.  rev the list, if you don't like the order.*)

  fun redundant_rules (nodes : node list)   : int list =
	List.foldL (fn node => fn is =>
		    (case node of
		       {kind=Success (_, i), refs=ref 0, ...} => i :: is
		     | _ => is))
	  [] nodes
		           

(*TODO 06/01/1998 11:25. tho.:

  fun string_from_decdag (edge : edge) =
	"(" ^ string_from_edge edge ^ ",\n[" ^ string_from_nodes reachable edge ^ "])\n"
  and string_from_edge NONE = "NONE"
    | string_from_edge (SOME (lvar, decision1)) =
	"SOME (" ^ Lvars.pr_lvar lvar ^ ", " ^ string_from_decison1 decision1 ^ ")"
  and string_from_nodes nodes = List.foldR (fn node => fn s =>
					string_from_node node ^ ",\n" ^ s) "" nodes
  and string_from_node (lvar, decision1) =
	"  (" ^ Lvars.pr_lvar lvar ^ "-- " ^ string_from_decison1 decision1 ^ ")"
  and string_from_decison1 (IfEq (path, con, t1, t2)) =
	"IfEq (" ^ string_from_path path ^ ", "
	^ string_from_con0 con ^ ", "
	^ short_string_from_edge t1 ^ ", "
	^ short_string_from_edge t2 ^ ")"
    | string_from_decison1 (Success rhs) = "Success " ^ string_from_rhs rhs
  and short_string_from_edge NONE = "NONE"
    | short_string_from_edge (SOME (lvar, _)) = "SOME (" ^ Lvars.pr_lvar lvar ^ ", ...)"

  val pr_decdag = pr o string_from_decdag
*)


  local
    fun declarations_to_be_made_for_id (id : id) (info : ElabInfo.ElabInfo) (path : path) =
	  (case to_TypeInfo info of
	     SOME (TypeInfo.VAR_PAT_INFO {tyvars, Type}) =>
	       let val alphas = map compileTyVar tyvars
		   val tau = compileType Type
		   val lvar = new_lvar_from_id id
	       in
		 (id, (lvar, alphas, tau), path)
	       end
	   | _ => die "declarations_to_be_made_for_id")

    (*declared_by_pat (pat, Obj) = the list of declarations (i.e.,
     declarations_to_be_made) that pat will make.  For instance, the pat in

      `fun f (a, b as (1, c)) = e'

     declares a, b & c.*)

    fun declared_by_pat (pat : pat, path : path) =
	  (case pat of
	     ATPATpat (info, atpat) => declared_by_atpat (atpat, path)
	   | CONSpat (info, longid_op_opt, atpat) =>
	       (case to_TypeInfo info of
		  SOME (TypeInfo.CON_INFO {numCons, longid, ...}) => 
		    declared_by_application (Con {longid=longid, span=span_from_int numCons,
				    info=info,
				    (*because it appears in a CONSpat:*)nullary=false})
		      [(0, ATPATpat (DecGrammar.bogus_info, atpat))] (path)
		| SOME (TypeInfo.EXCON_INFO {Type, longid}) =>
		    declared_by_application (Excon {longid=longid,
				      (*because it appears in a CONSpat:*)nullary=false})
		      [(0, ATPATpat (DecGrammar.bogus_info, atpat))] (path)
		 | _ => die "declared_by_pat (CONSpat ...)")
	   | TYPEDpat (info, pat, ty) => declared_by_pat (pat, path)
	   | LAYEREDpat (info, OP_OPT (id, _), ty_opt, pat) =>
	       declarations_to_be_made_for_id id info path :: declared_by_pat (pat, path)
	   | UNRES_INFIXpat _ => die "declared_by_pat (UNRES_INFIXpat ...)")

    and declared_by_atpat (atpat, path) =
	  (case atpat of
	     WILDCARDatpat info => []
	   | SCONatpat (info, scon) => []
	   | LONGIDatpat (info, OP_OPT (longid, _)) =>
	       (case to_TypeInfo info of
		  SOME (TypeInfo.VAR_PAT_INFO {tyvars, Type}) =>
		    (*it is a variable, not a nullary constructor*)
		    [declarations_to_be_made_for_id (Ident.decompose0 longid) info path]
		| SOME (TypeInfo.CON_INFO _) =>
		    (*because it appears in a LONGIDatpat, the constructor is nullary,
		     & thus has no arguments:*) [] 
		| SOME (TypeInfo.EXCON_INFO {Type, longid}) => []
		| _ => die "declared_by_atpat (LONGIDatpat ...)")
	   | RECORDatpat (info, patrow_opt) =>
	       let val patrows = (case patrow_opt of
			 NONE => []
		       | SOME patrow => makeList
			   (fn PATROW (_, _, _, patrow_opt) => patrow_opt
			     | DOTDOTDOT _ => die "declared_by_atpat: DOTDOTDOT")
			   patrow)
		 val argpats =
		       map (fn PATROW (info, _, pat, _) =>
			    (case to_TypeInfo info of
			       SOME (TypeInfo.LAB_INFO {index, ...}) => (index, pat)
			     | _ => die "declared_by_atpat: RECORDatpat info")
			     | _ => die "declared_by_atpat: RECORDatpat patrow") patrows
	       in
		 declared_by_application (Tuple {arity=List.size argpats}) argpats (path)
	       end
	   | PARatpat (info, pat) => declared_by_pat (pat, path))

    (*declared_by_application pcon argpats path = `pcon' is the compile-time
     description of the constructor that we want to generate code to match.
     `argpats' are the argument patterns to `pcon', each paired with its
     "Access number", the argument to the constructor Access that will access
     the component corresponding to that pattern.*)

    and declared_by_application pcon (argpats : (int * pat) list) path =
	  List.foldR (fn (i, pat) => fn declarations_to_be_made =>
		      declared_by_pat (pat, Access (i, pcon, path))
		      @ declarations_to_be_made) [] argpats
  in
    fun mk_success_node (pat : pat, rhs : rhs) : node =
	  let val rhs' = (declared_by_pat (pat, Obj), rhs)
	  in
	    mk_node (Success rhs') ("rhs" ^ string_from_rhs' rhs')
	  end

    fun simple_pat (ATPATpat (_, atpat)) = simple_atpat atpat
      | simple_pat (TYPEDpat (_, pat, _)) = simple_pat pat
      | simple_pat _ = NONE
    and simple_atpat (LONGIDatpat (info, OP_OPT (longid, _))) =
      (case to_TypeInfo info 
	 of SOME (TypeInfo.VAR_PAT_INFO _) => (*it is a variable, not a nullary constructor*)
	   SOME(Ident.decompose0 longid)
	  | _ => NONE)
      | simple_atpat (PARatpat (_, pat)) = simple_pat pat
      | simple_atpat _ = NONE

  end(*local*)


  fun mk_decdag (rules : rule list)   : edge =
	(reset () ;
	 let val edge = fail (Neg negset.empty, rules)
	 in
	   edge_bump edge ;
	   edge
	 end) 

  (*env_from_decdag is only used by compile_binding.  The decdag will always
   be from a pattern that only has one rhs, and env_from_decdag extracts from
   the decdag the environment in which this rhs expression must be
   compiled.*)

  fun env_from_decdag decdag = (*because the pattern is from a let-binding
				there will always be exactly one Success node.
				we grab the environment from that node:*)
	(case List.all (fn {kind=Success _, ...} => true | _ => false)
	        (reachable decdag) of
	   [{kind=Success (declarations_to_be_made, _), ...}] =>
	     env_from declarations_to_be_made
	 | _ => die "env_from_decdag: not exactly a Success")

end; (*match compiler local*)





    (* ---------------------------------------------------------------------- *)
    (*         Primitives for overloaded arithmetic operators                 *)
    (* ---------------------------------------------------------------------- *)


    local 
      fun int_or_real info (int, real) =
	    (case NoSome "int_or_real" (ElabInfo.to_OverloadingInfo info) of
	       OverloadingInfo.RESOLVED_INT => int
	     | OverloadingInfo.RESOLVED_REAL => real
	     | OverloadingInfo.RESOLVED_WORD8 => int
	     | OverloadingInfo.RESOLVED_WORD => int
	     | OverloadingInfo.RESOLVED_CHAR => int
	     | OverloadingInfo.RESOLVED_STRING => die "int_or_real: string"
	     | _ => die "int_or_real: unresolved")
      fun string_or_int_or_real info (int, real, string) =
	    (case NoSome "string_or_int_or_real" (ElabInfo.to_OverloadingInfo info) of
	       OverloadingInfo.RESOLVED_INT => int
	     | OverloadingInfo.RESOLVED_REAL => real
	     | OverloadingInfo.RESOLVED_WORD8 => int
	     | OverloadingInfo.RESOLVED_WORD => int
	     | OverloadingInfo.RESOLVED_CHAR => int
	     | OverloadingInfo.RESOLVED_STRING => string
	     | _ => die "string_or_int_or_real: unresolved")

      fun div_etc_ccall name =
	    CCALLprim {name = name, instances = [], tyvars = [],
		       Type = ARROWtype ([intType, intType, exnType], [intType])}
      fun string_ccall name =
	    CCALLprim {name = name, instances = [], tyvars = [],
		       Type = ARROWtype ([stringType, stringType], [boolType])}
      fun unoverload i CE.ABS = int_or_real i (ABS_INTprim, ABS_REALprim)
	| unoverload i CE.NEG = int_or_real i (NEG_INTprim, NEG_REALprim)
	| unoverload i CE.PLUS = int_or_real i (PLUS_INTprim, PLUS_REALprim)
	| unoverload i CE.MINUS = int_or_real i (MINUS_INTprim, MINUS_REALprim)
	| unoverload i CE.MUL = int_or_real i (MUL_INTprim, MUL_REALprim)
	| unoverload i CE.DIV = div_etc_ccall "divInt"
	| unoverload i CE.MOD = div_etc_ccall "modInt"
	| unoverload i CE.LESS =
	    string_or_int_or_real i
	      (LESS_INTprim, LESS_REALprim, string_ccall "lessString")
	| unoverload i CE.GREATER=
	    string_or_int_or_real i
	      (GREATER_INTprim, GREATER_REALprim, string_ccall "greaterString")
	| unoverload i CE.LESSEQ =
	    string_or_int_or_real i
	      (LESSEQ_INTprim, LESSEQ_REALprim, string_ccall "lesseqString")
	| unoverload i CE.GREATEREQ =
	    string_or_int_or_real i
	      (GREATEREQ_INTprim, GREATEREQ_REALprim, string_ccall "greatereqString")
	| unoverload i _ = die "unoverload"
    in
      fun overloaded_prim info result (*e.g., CE.ABS*)
	    compilerAtexp compilerExp (arg: DecGrammar.atexp)
	    takes_one_argument exn_args =
	    if takes_one_argument then
	      let val arg' = compilerAtexp arg
	      in PRIM (unoverload info result, [arg'])
	      end
	    else
	      (case arg of 
		 RECORDatexp(_,
			     SOME(EXPROW(_,_,exp1,
					 SOME(EXPROW(_,_,exp2,NONE))))) =>
		 let val exp1' = compilerExp exp1
		     val exp2' = compilerExp exp2
		 in PRIM (unoverload info result, [exp1',exp2'] @ exn_args)
		 end
	       | _ => die "overloaded_prim")

      fun overloaded_prim_fn info result (*e.g., CE.ABS*)
	    takes_one_argument exn_args =
	    let val ty = int_or_real info (CONStype ([], TyName.tyName_INT),
					   CONStype ([], TyName.tyName_REAL))
	        val lvar1 = Lvars.newLvar ()
	    in
	      if takes_one_argument then
		FN {pat=[(lvar1, ty)],
		    body=PRIM (unoverload info result,
			       [VAR {lvar=lvar1, instances=[]}])}
	      else (*takes two arguments*)
		FN {pat=[(lvar1, RECORDtype [ty, ty])],
		    body=PRIM (unoverload info result,
			       [PRIM (SELECTprim 0,
				      [VAR {lvar=lvar1, instances=[]}]),
				PRIM (SELECTprim 1,
				      [VAR {lvar=lvar1, instances=[]}])]
			       @ exn_args)}
	    end
      fun overloaded_prim_fn' info result = (*e.g., CE.LESS, ... *)
	    let val ty = CONStype ([], string_or_int_or_real info (TyName.tyName_INT,
								   TyName.tyName_REAL,
								   TyName.tyName_STRING))
	        val lvar1 = Lvars.newLvar ()
	    in (*takes two arguments*)
	      FN {pat=[(lvar1, RECORDtype [ty, ty])],
		  body=PRIM (unoverload info result,
			     [PRIM (SELECTprim 0,
				    [VAR {lvar=lvar1, instances=[]}]),
			      PRIM (SELECTprim 1,
				    [VAR {lvar=lvar1, instances=[]}])])}
	    end
    end (*local*)


    (* ----------------------------------------------------------------------- *)
    (*               Syntax directed compilation                               *)
    (* ----------------------------------------------------------------------- *)

    fun compileAtexp env atexp : TLE.LambdaExp =
          (case atexp of
	     SCONatexp(_, SCon.INTEGER x) => INTEGER x
	   | SCONatexp(_, SCon.STRING x) => STRING x
	   | SCONatexp(_, SCon.REAL x) => REAL x
	   | SCONatexp(_, SCon.CHAR x) => INTEGER x
	   | SCONatexp(_, SCon.WORD x) => INTEGER x
	   | IDENTatexp(info, OP_OPT(longid, _)) =>
	       compile_ident info longid (lookupLongid env longid (NORMAL info))

	   (* records: the fields must be evaluated in their textual order,
	    but the resulting record object must have the fields in a
	    canonical order (we adopt alphabetic ordering). Hmm. Tricky.
	    Easiest way is to bind the record field expressions to lvars and
	    then build a record of the (appropriately ordered) lvars. *)

	   (* Well, - if the labs are already sorted then we can in-line
	    the expressions in the record... 04/10/1996-Martin. *)

	   | RECORDatexp(_, SOME exprow) =>
	     let
               val rows = makeList (fn EXPROW(_, _, _, e) => e) exprow
               val labs = map (fn EXPROW(_, l, _, _) => l) rows
	       val exps = map (fn EXPROW(_, _, e, _) => compileExp env e) rows
	       fun is_sorted (l1::(labs as l2::_)) = Lab.<(l1,l2) andalso is_sorted labs
		 | is_sorted _ = true
	     in if is_sorted labs then PRIM(RECORDprim, exps) 
		else
		  let val taus = map (compileType o type_of_exp 
				      o (fn EXPROW(_,_,e,_) => e)) rows
		      val lvars = map (fn _ => Lvars.newLvar()) rows
		      val scope =              (* The final record expression *)
			let val sortedLvarsXlabs =
			          ListSort.sort
				  (fn (_, l1) => fn (_, l2) => Lab.<(l1, l2))
				  (ListPair.zip(lvars, labs))
			in
			  PRIM(RECORDprim,map (fn (lv, _) => VAR{lvar=lv,instances=[]})
			       sortedLvarsXlabs)
			end
		  in
		    List.foldR (fn (lv,exp,tau) => fn exp' => monoLet((lv,tau,exp),exp'))
		    scope (zip3(lvars,exps,taus))
		  end
	     end

	   | RECORDatexp(_, NONE) => PRIM(RECORDprim,[])

	   | LETatexp(_, dec, exp) =>
	       let val (env1, f) = compileDec env (false,dec)
	           val exp' = compileExp (env plus env1) exp
	       in f exp'
	       end

	   | PARatexp(_, exp) => compileExp env exp)

    and compile_ident info longid result =
          (case result of
	     CE.LVAR (lv,tyvars,_,il) =>   (*see COMPILER_ENV*) 
	       (let val instances =
		      (case to_TypeInfo info of
			 SOME(TypeInfo.VAR_INFO{instances}) => instances
		       | _ => die ("compileAtexp(LVAR..): no type info for "
				   ^ Ident.pr_longid longid))
		    val instances' = map compileType instances
		    val S = CE.mk_subst (fn () => "CompileDec.IDENTatexp") (tyvars, instances')
		    val il' = CE.on_il(S,il)
		in VAR {lvar=lv,instances=il'}
		end handle X => (print (" Exception raised in CompileDec.IDENTatexp.LVAR.longid = "
					^ Ident.pr_longid longid ^ "\n");
		                 print " Reraising...\n"; raise X))
	   | CE.ABS =>       overloaded_prim_fn info CE.ABS       true  []
	   | CE.NEG =>       overloaded_prim_fn info CE.NEG       true  []
	   | CE.PLUS =>      overloaded_prim_fn info CE.PLUS      false []
	   | CE.MINUS =>     overloaded_prim_fn info CE.MINUS     false []
	   | CE.MUL =>       overloaded_prim_fn info CE.MUL       false []
	   | CE.DIV =>       overloaded_prim_fn info CE.DIV       false
		  [PRIM (EXCONprim Excon.ex_DIV, [])]
	   | CE.MOD =>       overloaded_prim_fn info CE.MOD       false
		  [PRIM (EXCONprim Excon.ex_MOD, [])]
	   | CE.LESS =>      overloaded_prim_fn' info CE.LESS
	   | CE.GREATER =>   overloaded_prim_fn' info CE.GREATER
	   | CE.LESSEQ =>    overloaded_prim_fn' info CE.LESSEQ
	   | CE.GREATEREQ => overloaded_prim_fn' info CE.GREATEREQ
	   | CE.CON(con,tyvars,_,il,it) => (*See COMPILER_ENV*)
	       let
		 val (functional,Type,instances) =
		   case to_TypeInfo info 
		     of SOME (TypeInfo.CON_INFO{Type,instances,...}) =>
		       (Type.is_Arrow Type, Type, instances)
		      | _ => die "compileAtexp(CON..): no type info"
	       in if functional then
		    let val lv = Lvars.newLvar()
		        val tau' = compileType (domType Type)
			val instances' = map compileType instances
			val S = CE.mk_subst (fn () => "CompileDec.CON(arg)") (tyvars, instances')
			val il' = CE.on_il(S,il)
			val il'' = CE.apply_it(it,il')
		    in FN{pat=[(lv,tau')],
			  body=PRIM(CONprim{con=con, instances=il''},
				    [VAR{lvar=lv,instances=[]}])}
		    end
		  else
		    let val instances' = map compileType instances
		        val S = CE.mk_subst (fn () => "CompileDec.CON(noarg)") (tyvars, instances')
			val il' = CE.on_il(S,il)
			val il'' = CE.apply_it(it,il')
		    in PRIM(CONprim {con=con, instances=il''},[])
		    end
	       end
	   | CE.REF =>
	       let val (Type,instances) =
		     case to_TypeInfo info 
		       of SOME (TypeInfo.CON_INFO{Type,instances,...}) => (Type,instances)
			| _ => die "compileAtexp(REF..): no type info"
		   val lv = Lvars.newLvar()
		   val instance = case instances 
				    of [x] => x 
				     | _ => die "compileAtexp(REF..): wrong ref instance"
		   val tau' = compileType (domType Type)
		   val instance' = compileType instance
	       in FN{pat=[(lv,tau')],
		     body=PRIM(REFprim {instance=instance'},
			       [VAR{lvar=lv,instances=[]}])}
	       end
	   | CE.EXCON (excon,_) =>
	       let
		 val (functional,Type) =
		   case to_TypeInfo info of 
		     SOME (TypeInfo.EXCON_INFO{Type,...}) => 
		       (Type.is_Arrow Type,Type)
		   | _ => die "compileAtexp(EXCON..): no type info"
	       in         
		 if functional then
		   let val lv = Lvars.newLvar()
		       val tau' = compileType (domType Type)
		   in FN{pat=[(lv,tau')],
			 body=PRIM(EXCONprim excon,
				   [VAR{lvar=lv, instances=[]}])}
		   end
		 else PRIM(EXCONprim excon,[])
	       end
	   | CE.RESET_REGIONS => die "compile_ident: CE.RESET_REGIONS"
	   | CE.FORCE_RESET_REGIONS => die "compile_ident: CE.FORCE_RESET_REGIONS"
	   | CE.PRIM => die "compile_ident: CE.PRIM")

    and compileExp env exp =
          (case exp of
	     ATEXPexp(_, atexp) => compileAtexp env atexp

	   | APPexp(_, f as ATEXPexp(_, IDENTatexp(info, OP_OPT(longid, _))), arg) =>
	       compile_application_of_ident env f info longid arg

	   | APPexp(_, f, arg) => (*application of non-identifier*)
	       let val f' = compileExp env f
		 val arg' = compileAtexp env arg
	       in APP(f',arg')
	       end

	   | TYPEDexp(_, exp, _) => compileExp env exp

	   | HANDLEexp (info, exp', match) =>
	       let val e1' = compileExp env exp'
		   val tau_return = compileType (type_of_exp exp)
		   val e2' = compile_match env
		                (info,
				 match,
				 (*no inexhaustiveness warnings:*)false,
				 SOME tau_return,
				(*when no mrule matches, the raised exception
				 (obj, which is not known here)
				 must be reraised:*)
				fn obj => RAISE (obj, Types [tau_return]))
	       in HANDLE (e1',e2')
	       end

	   | RAISEexp(i, exp') => 
	       let val e' = compileExp env exp'
		   val tau' = compileType (type_of_exp exp)
	       in RAISE(e',Types [tau'])
	       end

	   | FNexp (info, match) => 
	       let val tau_return = 
		         (case compileType (type_of_exp exp) of
			    ARROWtype (_, [tau_return]) => tau_return
			  | _ => die "compileExp: FNexp did not have (unary) arrow type")
	       in compile_match env (info,
				     match,
				     (*inexhaustiveness warnings, please:*)true,
				     SOME tau_return,
				    (*when no mrule matches, exception Match must
				     be raised: (abstracted over obj because
				     of HANDLEexp above)*)
				    fn obj =>
				    RAISE (PRIM (EXCONprim Excon.ex_MATCH, []),
					   Types [tau_return]))
	       end

	   | UNRES_INFIXexp _ =>  die "compileExp(UNRES_INFIX)")

   
    and compile_application_of_ident env f info longid arg =

          (* We have to spot direct application of "prim" - apart from that,
	   we don't have to bother with constructors and the like. They'll
	   compile to functions, but the optimiser will spot them later. *)
	  
          (case lookupLongid env longid (NORMAL info) of
	     CE.LVAR (lv,tyvars,_,il) =>        (* Not a primitive... *)
		let val arg' = compileAtexp env arg
		    val instances' = case to_TypeInfo info 
				       of SOME(TypeInfo.VAR_INFO{instances}) =>
					 map compileType instances
					| _ => die "compileExp(APPexp..): wrong type info"
		    val S = CE.mk_subst (fn () => ("CompileDec.APPexp.LVAR("
						   ^ Lvars.pr_lvar lv ^ ")"))
		              (tyvars,instances')
		    val il' = CE.on_il(S, il)
		in if Lvars.pr_lvar lv = "="  (* specialise equality on integers *)
                      andalso case instances' of 
                                [CONStype([], tyname)] => TyName.eq(tyname, TyName.tyName_INT)
                              | _ => false
                   then PRIM(EQUAL_INTprim, case arg' of
                                          PRIM(RECORDprim,l ) => l
                                         | _ => die "compileExp(APPexp..): expected pair")
                   else
                     APP(VAR{lvar=lv,instances=il'},arg')
		end

	    | CE.RESET_REGIONS =>
		let val arg' = compileAtexp env arg
		    val tau' = case to_TypeInfo info 
				 of SOME(TypeInfo.VAR_INFO{instances = [tau]}) =>
				   compileType tau
				  | _ => die "compileExp(APPexp..): wrong type info"
		in PRIM(RESET_REGIONSprim{instance = tau'}, [arg'])
		end

	    | CE.FORCE_RESET_REGIONS =>
		let val arg' = compileAtexp env arg
		    val tau' = case to_TypeInfo info 
				 of SOME(TypeInfo.VAR_INFO{instances = [tau]}) =>
				   compileType tau
				  | _ => die "compileExp(APPexp..): wrong type info"
		in PRIM(FORCE_RESET_REGIONSprim{instance = tau'}, [arg'])
		end

	    | CE.ABS =>       overloaded_prim info CE.ABS       (compileAtexp env) (compileExp env) arg true  []
	    | CE.NEG =>       overloaded_prim info CE.NEG       (compileAtexp env) (compileExp env) arg true  []
	    | CE.PLUS =>      overloaded_prim info CE.PLUS      (compileAtexp env) (compileExp env) arg false []
	    | CE.MINUS =>     overloaded_prim info CE.MINUS     (compileAtexp env) (compileExp env) arg false []
	    | CE.MUL =>       overloaded_prim info CE.MUL       (compileAtexp env) (compileExp env) arg false []
	    | CE.DIV =>       overloaded_prim info CE.DIV       (compileAtexp env) (compileExp env) arg false
		[PRIM (EXCONprim Excon.ex_DIV, [])]
	    | CE.MOD =>       overloaded_prim info CE.MOD       (compileAtexp env) (compileExp env) arg false 
		[PRIM (EXCONprim Excon.ex_MOD, [])]
	    | CE.LESS =>      overloaded_prim info CE.LESS      (compileAtexp env) (compileExp env) arg false []
	    | CE.GREATER =>   overloaded_prim info CE.GREATER   (compileAtexp env) (compileExp env) arg false []
	    | CE.LESSEQ =>    overloaded_prim info CE.LESSEQ    (compileAtexp env) (compileExp env) arg false []
	    | CE.GREATEREQ => overloaded_prim info CE.GREATEREQ (compileAtexp env) (compileExp env) arg false []
	    | CE.PRIM => compile_application_of_prim env info arg
     
	    | _ (*CON/EXCON*) => let val f' = compileExp env f
	                             val arg' = compileAtexp env arg
				 in APP(f',arg')
				 end
            ) (*fun compile_application_of_ident*)


    and compile_application_of_prim env info atexp =

          (*Application of `prim' to atexp.  We disassemble atexp to get the
	   name s of the primitive operation and its arguments.*)

          (let val (s, args) = decompose_prim_call atexp
	       fun f isequal prim =
		     let val args' = map (compileExp env) args
		         val instance' = (case to_TypeInfo info of
			       SOME (TypeInfo.VAR_INFO {instances = [instanceRes, instance]}) =>
				 compileType instance 
			     | _ => die "compileExp(APPexp(PRIM..): wrong type info")
		        (*The code right above depends on the order of the
			 instances recorded during elaboration.  We need the
			 instance corresponding to the argument of prim,
			 which in EfficientCoreElab version is the second*)
                
                        (* Specialice EQUALprim to EQUAL_INTprim, when possible *)
                        val prim' = case (isequal,instance') of
                                      (true,CONStype([], tyname)) =>
                                        if TyName.eq(tyname,TyName.tyName_INT) then EQUAL_INTprim 
                                        else prim {instance=instance'}
                                    | _ => prim {instance=instance'}
		     in TLE.PRIM (prim', args')
		     end
(*TODO 12/11/1997 18:37. tho.:
the 12 lines above are very similar to the code below
*)
	   in
	     (case s of
		"!" => f false DEREFprim (*ref (REFprim) is a constructor, so it does not show up here*)
	      | ":=" => f false ASSIGNprim
	      | "=" => f true EQUALprim

(*KILL 20/11/1997 15:38. tho.:
 it is wrong to remove "id" here; now it is done in CompLamb.
	      | "id" => 
		  (*type conversions that result in no code to run at
		   run-time are declared as prim "id"'s; for instance, ord is
		   defined: `fun ord (c : char) : int = prim ("id", "id", c)'.*)
		  (case args of
		     [exp] => compileExp env exp
		   | _ => die "compile_application_of_prim: prim id")
*)
	      | _ => 
		  (*unrecognised prim name: this must be a c call; let us
		   hope the run-time system defines a function called s:*)
		  compile_application_of_c_function env info s args)
	   end) (*fun compile_application_of_prim*)

    and compile_application_of_c_function env info s args =
          (case to_TypeInfo info of
	     SOME (TypeInfo.VAR_INFO {instances = [tau_result, tau_argument]}) =>
	       
	       (*Concerning instance lists on c calls:  The built-in id
		`prim' has type scheme `All'a'b.(string * string * 'a)->'b'.
		In ElabDec it was instantiated, and the list instances above
		is the types to which 'a and 'b were instantiated: 'b was
		instantiated to tau_result, 'a to tau_argument (yes, it is a
		bit messy).  Thus the type of the c function is
		tau_argument->tau_result.  From CompileDec and on, we want
		the instance list to be the instance list of the c function
		type rather than the instance list of the type of `prim':*)
	       let val taus1 =
		     (case compileType tau_argument of tau1 =>
			(case List.size args of
			   1 => [tau1]
			 | n => (case tau1 of
				   TLE.RECORDtype taus1 =>
				     if List.size taus1 = n then taus1
				     else die ("prim " ^ s ^ " has wrong number of arguments")
				 | _ => die ("give prim " ^ s ^ " a record argument type"))))
		   val tau2 = compileType tau_result
		   val tau = TLE.ARROWtype (taus1, [tau2])
		   val tyvars = EqSet.list (LambdaExp.tyvars tau)
		   val tyvars_fresh = map (fn tyvar => LambdaExp.fresh_tyvar ()) tyvars
		   val subst = LambdaBasics.mk_subst
		                 (fn () => "CompileDec.compile_application_of_c_function")
		                    (tyvars, map TLE.TYVARtype tyvars_fresh)
	       in
		 TLE.PRIM (CCALLprim {name = s,
				      tyvars = tyvars_fresh,
				      Type = LambdaBasics.on_Type subst tau,
				      instances = map TLE.TYVARtype tyvars},
		           map (compileExp env) args)
	       end
	   | _ => die "compile_application_of_prim: wrong type info in ccall")


    (*flatten_c_function_type ([t1 * t2] -> [t3]) = [t1, t2] -> [t3]*)
    and flatten_c_function_type (TLE.ARROWtype ([TLE.RECORDtype taus1], taus2)) =
          TLE.ARROWtype (taus1, taus2)
      | flatten_c_function_type (TLE.ARROWtype (taus1, taus2)) =
	  TLE.ARROWtype (taus1, taus2)
      | flatten_c_function_type _ = die "flatten_c_function_type: not arrow"


    (*decompose_prim_call atexp = the name (string) of the called prim & the
     argument exps.  atexp is the atexp after `prim'.  A prim call has the
     form `prim ("f", "fprof", (e1, e2))' assuming the name of the function in
     the runtime system to call is f (and fprof, when profiling is turned
     on), & that f (and fprof) takes two arguments.*)

    and decompose_prim_call
          (RECORDatexp (_, SOME (EXPROW (_, _,
           ATEXPexp (_, SCONatexp (_, SCon.STRING s1)), SOME (EXPROW (_, _,
           ATEXPexp (_, SCONatexp (_, SCon.STRING s2)), SOME (EXPROW (_, _,
           exp3, NONE)))))))) =
	  (if !region_profiling then s2 else s1, decompose_prim_args exp3)
      | decompose_prim_call _ =
	  die ("\n\nRemember to give two function names in quotes in the declaration of \
	       \a prim.\nMaybe you forgot the profiling function name.")
    and decompose_prim_args (ATEXPexp (_, RECORDatexp (_, exprow_opt))) =
          decompose_prim_args0 exprow_opt
      | decompose_prim_args exp = [exp]
    and decompose_prim_args0 NONE = []
      | decompose_prim_args0 (SOME (EXPROW (_, _, e1, exprow_opt))) =
          e1 :: decompose_prim_args0 exprow_opt


    (*compile_match = compile a match into a FN expression; this is used for
     FNexp & HANDLEexp expressions.  `raise_something' indicates what to
     plant for non-matches; it can be either a lexp that raises exception
     Match or reraises the raised exception.  `warn_on_inexhaustiveness' is
     true, e.g., for case statement on excons, but false for the equivalent
     in a handler.  The `info' is for pretty warnings.  Well, it does not
     really make them prettier.*)

    and compile_match env (info, match, warn_on_inexhaustiveness,
			   tau_return_opt, raise_something) =
      let
	val matches = makeList (fn MATCH(_, _, m) => m) match
	val pats = map (fn MATCH(_, MRULE(_, pat, _), _) => pat) matches
	val exps = map (fn MATCH(_, MRULE(_, _, exp), _) => exp) matches
	val tab = List.tabulate (List.size pats, fn i => i)
	val pat_rhs_s = ListPair.zip (pats, tab)
                 handle ListPair.Zip => die "compile_match: zip"
	val rules = map (fn (pat, rhs) => (pat, mk_success_node (pat, rhs)))
	               pat_rhs_s
	val decdag = mk_decdag rules
	val lvar_switch = new_lvar_from_pats pats
	val obj = VAR {lvar=lvar_switch, instances=[]}
	      (*instances=[] because the argument to a fn cannot be polymorphic*)
	val tau_argument = compileType (domType (type_of_match match))
	val compile_no = fn (i, env_rhs) =>
	                 (compileExp env_rhs (List.nth i exps
					      handle _ => die "compile_match: nth"))
	val (functions, lexp) =
	      compile_decdag  compile_no obj raise_something tau_return_opt env decdag
      in
	(*KILL 21/12/1997 18:44. tho.:
	 pr "\n\ncompileMatch: decdag is:\n";
	 pr_decdag decdag;
	 *)
	if not warn_on_inexhaustiveness orelse exhaustive (reachable decdag) then () else
	  Flags.warn
	  (report_SourceInfo info // line "Match not exhaustive.") ;
        List.apply (fn i (*number of rhs which is redundant*) =>
		    (case (List.nth i matches handle _ => die "compile_match: 2nd nth") of
		       MATCH (_, MRULE (info, _, _), _) => 
			 Flags.warn (report_SourceInfo info
				     // line "That rule is redundant.")))
	  (redundant_rules (map #2 rules)) ;
	FN {pat = [(lvar_switch, tau_argument)],
	    body = FIX {functions = functions, scope = lexp}}
      end
(*KILL 25/11/1997 15:07. tho.:
         val decTree = matchCompiler compileTypeScheme 
	   (root, pats, {warnInexhaustive=warn, warnNoBindings=false})

         fun f(n: int, e: CE.CEnv): LambdaExp =
           compileExp (env plus e) (List.nth (n-1) exps)

         val env' = CE.declareLvar(root,[],env)
         val exp =
            compileDecTree env' (decTree, f,
                                case failure
                                  of RAISEMATCH tau' => raiseMatch tau'
                                   | RAISESELF tau' => RAISE(VAR{lvar=root,instances=[]},
                                                             Types [tau']),
                                false) 
                (* last argument is false as the variables bound in the match
		 * are to be FN bound in the lambda language (monomorphic) *)
	 val tau = compileType (domType (type_of_match match))
      in FN{pat=[(root,tau)], body=exp}
      end
*)




   (*compileDec - takes an enclosing environment and a declaration, and
    returns the environment *for this declaration only*, together with a
    function to apply to the declaration's scope to return the entire lambda
    term.  The `topLevel' parameter is only needed because the match compiler
    is expected to report non-binding patterns for non top-level val bindings
    only.  (I think it is always true, right now... and probably will be
    forever.)*)

    and compileDec env (topLevel, dec): (CE.CEnv * (LambdaExp -> LambdaExp)) =
      case dec
        of VALdec(_, tyvars, valbind) =>
	   compileValbind env (topLevel, valbind)

         | UNRES_FUNdec _ =>
             die "compileDec(UNRES_FUN)"

         | TYPEdec(i, typbind) => (compileTypbind i, fn x => x)

         | DATATYPEdec(i, _) => 
	     let val (env_ve, env_te, datbinds) = compileDatbind i
	         val _ = DatBinds.add datbinds
	     in (env_ve plus env_te, fn x => x)
	     end

	 | DATATYPE_REPLICATIONdec (i, tycon, longtycon) => 
	     let val env1 = 
	            case to_TypeInfo i 
		      of SOME(TypeInfo.TYENV_INFO TyEnv) =>
			(case TE.lookup TyEnv tycon    (* A datatype replication may or may not
							* introduce an empty VE component. *)
			   of SOME tystr => 
			     if VE.is_empty (TyStr.to_VE tystr) then
			       let val tns = (TyName.Set.list o TyName.Set.map compileTyName) (TyStr.tynames tystr)
			       in CE.declare_tycon(tycon,(tns,CE.emptyCEnv),CE.emptyCEnv)
			       end
			     else  (* if the VE is non-empty then we can look it up in env *)
			       let val (tynames, env_ve) = CE.lookup_longtycon env longtycon
			  	   val env_te = CE.declare_tycon(tycon, (tynames, env_ve), CE.emptyCEnv)
			       in env_ve plus env_te
			       end 
			    | NONE => die "DATATYPE_REPLICATIONdec: tycon not in env")
		       | _ => die "DATATYPE_REPLICATIONdec: No TyEnv type info"
	     in (env1, fn x => x)
	     end

         | ABSTYPEdec(i, _, dec) =>
	     let val (env_ve, env_te, datbinds) = compileDatbind i
	         val _ = DatBinds.add datbinds
		 val (env2, f) = compileDec (env plus (env_ve plus env_te)) (false,dec)
	     in (env_te plus env2, f)
	     end

         | EXCEPTIONdec(_, exbind) => compileExbind env exbind

         | LOCALdec(_, dec1, dec2) =>
             let val (env1, f1) = compileDec env (false,dec1)
	         val (env2, f2) = compileDec (env plus env1) (false,dec2)
	     in (env2, f1 o f2)
	     end

         | OPENdec(i,longstrids_withinfos) =>
	     let val longstrids = map (fn WITH_INFO(_,longstrid) => longstrid) longstrids_withinfos
	         val envs = map (lookup_longstrid env) longstrids
		 val env' = List.foldL (fn env => fn env' => env' plus env) CE.emptyCEnv envs
	     in (env', fn x => x)
	     end
 
         | SEQdec(_, dec1, dec2) =>
             let val (env1, f1) = compileDec env (topLevel,dec1)
	         val (env2, f2) = compileDec (env plus env1) (topLevel,dec2)
	     in (env1 plus env2, f1 o f2)
	     end

        (* INFIX/NONFIX declarations have no effect on execution. *)

         | INFIXdec _ => (CE.emptyCEnv, fn x => x)
         | INFIXRdec _ => (CE.emptyCEnv, fn x => x)
         | NONFIXdec _ => (CE.emptyCEnv, fn x => x)

         | EMPTYdec _ => (CE.emptyCEnv, fn x => x)

   (* compileValbind - although there may be `rec' prefixes nested anywhere
      in the valbind, the effect is a single non-recursive layer of
      binding, together with a second layer of several distinct recursive
      valbinds. *)

    and compileValbind env (topLevel, valbind)
        : (CE.CEnv * (LambdaExp -> LambdaExp)) =
      let
        fun flattenRecValbind vb: 
                       (pat * exp * (TyVar list * StatObject.Type)) list =
          case vb of 
            PLAINvalbind(i, pat, exp, vbOpt) =>
              (case to_TypeInfo i of 
                 SOME (TypeInfo.PLAINvalbind_INFO{Type,tyvars,...}) => 
                   (pat, exp,(tyvars,Type)) :: 
                   (case vbOpt of SOME vb => flattenRecValbind vb
                                | NONE    => nil)

               | _ => die "flattenRecValbind: no type info")

          | RECvalbind(_, vb) =>  flattenRecValbind vb
      in
        case valbind
          of PLAINvalbind(i, pat, exp, NONE) =>
            (case to_TypeInfo i
	       of SOME (TypeInfo.PLAINvalbind_INFO{tyvars,Type,...}) => 
		 compile_binding env (topLevel, pat, exp, (tyvars, Type))
		| _ => die "compileValbind: no type info")

           | PLAINvalbind(i, pat, exp, SOME vb) =>
               (case to_TypeInfo i
		  of SOME (TypeInfo.PLAINvalbind_INFO{tyvars,Type,...}) =>
		    let val (env1, f1) = compile_binding env (topLevel, pat, exp, (tyvars, Type))
		        val (envRest, f2) = compileValbind env (topLevel,vb)
		    in (env1 plus envRest, f1 o f2)
		    end
		   | _ => die "compileValbind: no type info")

           | RECvalbind(_, vb) =>
               let val triples = flattenRecValbind vb
               in compileREC env (unzip3 triples)
               end
      end


       (* A datatype declaration is compiled by compiling the semantic
        * object TyEnv associated with it. The type environment
        * (TyEnv) has been glued (as type info) to the syntactic
        * construct of the datatype declaration during elaboration.
        * Notice that the syntactic restrictions (see p. 9, The Def.)
        * ensures that no constructor identifier is bound twice by the
        * same datbind. *)
                          (* VE        TE *) 
    and compileDatbind i : CE.CEnv * CE.CEnv * datbind_list =
      case to_TypeInfo i 
	of SOME(TypeInfo.TYENV_INFO TyEnv) => 
	  TE.Fold (fn (tycon,tystr) => fn (env_ve, env_te, dats) => 
	       if VE.is_empty (TyStr.to_VE tystr) then die "compileDatbind"
	       else let val tyname = (NoSome "TypeFcn not simple" o 
				      TypeFcn.to_TyName o TyStr.to_theta) tystr
			val VE = TyStr.to_VE tystr
			val (env_ve', tyvars, cbs) = compile'TyStr' (tyname, VE) 
			val env_te' = CE.declare_tycon(tycon, ([tyname], env_ve'), env_te)
		    in (env_ve plus env_ve', env_te', (tyvars,tyname,cbs)::dats)
		    end) (CE.emptyCEnv,CE.emptyCEnv,[]) TyEnv
	 | _ => die "No TyEnv type info for compiling datbind"

    and compileTypbind i : CE.CEnv = 
      case to_TypeInfo i 
	of SOME(TypeInfo.TYENV_INFO TyEnv) =>
	  TE.Fold (fn (tycon, tystr) => fn env' => 
		   if VE.is_empty (TyStr.to_VE tystr) then
		     let val tns = TyStr.tynames tystr
			 val tns = TyName.Set.map compileTyName tns
		         val tns = TyName.Set.list tns
		     in CE.declare_tycon(tycon,(tns,CE.emptyCEnv),env')
		     end
		   else die "compileTypbind: expecting VE to be empty") CE.emptyCEnv TyEnv
	| _ => die "compileTypbind: No TyEnv type info"

    and compileExbind (env:CE.CEnv) exbind : (CE.CEnv * (LambdaExp -> LambdaExp)) =
      case exbind
        of EXBIND(i, OP_OPT(excon, _), _, rest) =>
             let val tyOpt = case to_TypeInfo i 
			       of SOME(TypeInfo.EXBIND_INFO {TypeOpt}) => TypeOpt 
				| _ => die "No typeOpt info for compiling exbind" 
		 val (env1, f1) = compileNewExn env excon tyOpt
		 val (envRest, f2) = case rest
				       of SOME exbind' => compileExbind env exbind'
					| NONE => (CE.emptyCEnv, fn x => x)
	     in (env1 plus envRest, f1 o f2)
             end

         | EXEQUAL(info, OP_OPT(excon1, _), OP_OPT(longexcon2, _), rest) =>
             let val (excon2', tau) = lookupLongexcon env longexcon2 (NORMAL info)
                 val env1 = declareExcon(excon1, (excon2', tau), CE.emptyCEnv)
		 val (envRest, f2) = case rest
				       of SOME exbind' => compileExbind env exbind'
					| NONE => (CE.emptyCEnv, fn x => x)
	     in (env1 plus envRest, f2) (*no new code*)
             end

    and compileNewExn env excon tyOpt =
      let val excon' = compileExCon excon
          val LambdaTypeOpt =
	    case tyOpt 
	      of NONE => NONE 
	       | SOME tau => SOME (compileType tau)
	  val tau = case LambdaTypeOpt
		      of SOME tau => TLE.ARROWtype([tau],[TLE.exnType])
		       | NONE => TLE.exnType 
	  val env1 = declareExcon(excon,(excon',tau),CE.emptyCEnv)
	  val f1 = fn x => EXCEPTION(excon',LambdaTypeOpt, x)
      in (env1,f1)
      end

   (*compile_binding: we are compiling something like

        `let val pat = exp in scope end'.

    compile_binding returns the environment established by `pat', and a
    function: LambdaExp->LambdaExp, which is applied to the `scope'
    expression to yield the entire let expression. This generalises to
    parallel (`and'-linked) bindings. As long as we get the environment
    handling right (and don't make the thing `rec' by mistake), we can
    finally just cascade together the result functions returned by
    compile_binding.  sigma is the type scheme of the exp, recorded during
    elaboration.*)

  (*When the pattern is from a valbind, i.e., something like

     `val <pat> = <exp>',

   we cannot generate a FIX with functions as we do when the pattern is from
   a `fn <pat> => ...' or a `... handle <pat>'.  In the latter cases we
   generate a FIX with functions to implement the finite automaton that
   matches a value against the pattern.  This means that the scope of the
   pattern ends up as a FIX-bound function body, and this will not do when
   the scope may be a FRAME, which the scope of a valbind may be.  Sorry
   about this messy explanation.

   No, it is better to explain this by giving examples of the code generated
   in the two situations.  TODO

   compile_binding maybe ought to, but does not, use the `topLevel'
   argument.
   
   We treat the case where the pattern is a simple variable as a
   special case; that is, in case we are compiling a binding of the
   form `vid = <exp>' (where vid does not have constructor status)
   then we do not call upon the pattern matcher. Instead, we construct
   the binding manually. ME 1998-08-23

   *)

    and compile_binding env (topLevel, pat, exp, (tyvars, Type))
        : CE.CEnv * (LambdaExp -> LambdaExp) =
      (case simple_pat pat
	 of SOME vid => 
	   let val lvar = Lvars.new_named_lvar (Ident.pr_id vid)
	       val (tyvars', tau') = compileTypeScheme (tyvars, Type)
	       val env' = CE.declareVar (vid, (lvar, tyvars', tau'), CE.emptyCEnv) 
	       val f = fn scope => LET {pat = [(lvar, tyvars', tau')],
					bind = compileExp env exp,
					scope = scope}
	   in (env', f)
	   end
	  | NONE => 
	   let 
	     val decdag = mk_decdag [(pat, mk_success_node (pat, 0))]
	     val f = fn scope =>
	       let val (tyvars', tau') = compileTypeScheme (tyvars, Type)
		   val lvar_switch = new_lvar_from_pat pat
		   val obj = VAR {lvar=lvar_switch, instances=map TYVARtype tyvars'}
		   fun compile_no (i, env_rhs) = scope
		   val raise_something = fn obj =>
		     RAISE (PRIM (EXCONprim Excon.ex_BIND, []), LambdaExp.RaisedExnBind)
	       in
		 case compile_decdag  compile_no obj raise_something NONE env decdag 
		   of ([], lexp) => LET {pat = [(lvar_switch, tyvars', tau')],
					 bind = compileExp env exp,
					 scope = lexp}
		    | _ =>
		     die "compile_binding: there should only be functions when there are\n\
		      \shared nodes in the decdag, i.e., nodes that are jumped to by\n\
		      \more than one node, and there can be no shared nodes in a decdag\n\
		      \from a valbind, because a valbind only has one rule (one pattern):\n\
		      \all jumps will either be to a fail node, the single success node,\n\
		      \or to the ``next'' ifeq node."
	       end
	     val env_rhs = env_from_decdag decdag
           in
	     if exhaustive (reachable decdag) then () else
	       Flags.warn
	       (report_SourceInfo (DecGrammar.get_info_pat pat)
		// line "Pattern not exhaustive.") ;
	       (env_rhs, f)
	   end
	 )

   (* compileREC - compile a list of `rec' pattern/expression pairs. The
      patterns must all be variables (and aren't even allowed to be
      bracketted??), and the RHS's must all be lambdas. Type constraints
      are allowed, though. Returns the rec env only, plus `fn scope -> lexp'. *)

    and compileREC env (pats, exps, sigmas): (CE.CEnv * (LambdaExp -> LambdaExp)) =
      let
        fun varOfPat(TYPEDpat(_, pat, _)) = varOfPat pat
          | varOfPat(ATPATpat(_, LONGIDatpat(_, OP_OPT(longid, _)))) =
              (case Ident.decompose longid
                 of (nil, id) => id
                  | _ => die("compileREC.varOfPat(long: "
			     ^ Ident.pr_longid longid ^ ")"))
          | varOfPat _ = die "compileREC.varOfPat"

        val ids = map varOfPat pats
        val lvars_with_dummies = 
	  map (fn id => (Lvars.new_named_lvar(Ident.pr_id id),[],TYVARtype (fresh_tyvar()))) ids
	val lvars = map #1 lvars_with_dummies
        val recEnv: CE.CEnv =  mk_env CE.declareVar (ids,lvars_with_dummies)

	fun mk_scope_env lvars sigmas' = 
	  mk_env (fn (id,(lvar,(tyvars,Type)),ce) => CE.declareVar(id,(lvar,tyvars,Type),ce))
	  (ids, ListPair.zip(lvars,sigmas'))

        fun mk_bindings lvars sigmas' binds =
          map (fn (lvar,(tyvars,Type),bind) => {lvar = lvar, tyvars=tyvars,
						Type=Type, bind=bind})
          (zip3(lvars,sigmas',binds))

	val lexps = map (compileExp (env plus recEnv)) exps
	val sigmas' = map compileTypeScheme sigmas
	val env' = mk_scope_env lvars sigmas'
	val f' = fn scope => FIX {functions=mk_bindings lvars sigmas' lexps,
				  scope=scope}
      in (env', f')
      end                                                            
(*KILL 15/12/1997 20:02. tho.:

    and compileSconSwitch env (arg: lvar,
                               selections: (scon * DecisionTree) list,
                               wildcard: DecisionTree,
                               compiler: (int * CE.CEnv) -> LambdaExp,
                               failure: LambdaExp,
                               poly
                              ): LambdaExp =
      let
        exception Next  (* wrong type of scon tried, try the next type. *)

        fun foldIntegerMap m =
          map (fn (SCon.INTEGER x, t) => (x, compileDecTree env (t, compiler,failure,poly))
                | _ => raise Next) 
          m

        fun foldStringMap m =
          map (fn (SCon.STRING x, t) => (x, compileDecTree env (t, compiler,failure,poly))
	        | _ => raise Next) 
          m

        fun foldCharMap m =
          map (fn (SCon.CHAR x, t) => (x, compileDecTree env (t, compiler,failure,poly))
	        | _ => raise Next) 
          m

        fun foldWordMap m =
          map (fn (SCon.WORD x, t) => (x, compileDecTree env (t, compiler,failure,poly))
	        | _ => raise Next) 
          m
      in

        let val selections' = foldIntegerMap selections
	    val w' = compileDecTree env (wildcard,compiler,failure,poly)
	in SWITCH_I(SWITCH(VAR{lvar=arg,instances=CE.lookupLvar env arg},
			   selections',SOME w'))
	end

        handle Next =>

	let val selections' = foldStringMap selections
	    val w' = compileDecTree env (wildcard,compiler,failure,poly)
	in SWITCH_S(SWITCH(VAR{lvar=arg,instances=CE.lookupLvar env arg},
			   selections',SOME w'))
	end

        handle Next =>

        let val selections' = foldCharMap selections
	    val w' = compileDecTree env (wildcard,compiler,failure,poly)
	in SWITCH_I(SWITCH(VAR{lvar=arg,instances=CE.lookupLvar env arg},
			   selections',SOME w'))
	end

        handle Next =>

	let val selections' = foldWordMap selections
	    val w' = compileDecTree env (wildcard,compiler,failure,poly)
	in SWITCH_I(SWITCH(VAR{lvar=arg,instances=CE.lookupLvar env arg},
			   selections',SOME w'))
	end

        handle Next => die "compileSconSwitch"
      end




     


   (* 
    * compileDecTree: 
    *    Note that compileDecTree doesn't take a list of abstract syntax
    * expressions as argument: we may not have one - compileDec isn't used
    * in that way at top-level. Nor does it take a list of compiled lambda
    * expressions: there is not necessarily a unique lambda for each RHS as
    * an RHS might be reachable several ways through a decision tree, so
    * the environment for generating the lambda isn't easily determined
    * elsewhere. So, it seems that the best bet is to pass `compileDecTree'
    * a function of type `(int * CE.CEnv) -> LambdaExp', which it can call at
    * each leaf point to generate a lambda for that rule with the decomposition
    * environment.
    *   poly signifies whether or not the variables that are bound in the decision
    * tree are allowed to be LET bound (poly true) or must be FN bound (poly false). 
    *   Whenever an lvar to be bound is encountered it is saved in the environment
    * together with the bound type variables corresponding to the lvar. This way
    * it is possible to obtain type instances of parents by looking up the variables
    * in the enviroment. The reason this holds is as follows. There will only be 
    * bound type variables when the decision tree has been generated for a pattern 
    * which is the left hand side pattern of a value binding (otherwise the 
    * decision tree is generated from a match in an FNexp or a HANDLEexp where we 
    * only have types and not type schemes).  We need the instances for a parent when
    * we refer to a parent (for instance when decomposing).  We simply assert that
    * the instances are equal to the bound variables of the parent, i.e. that the 
    * bound type variables are instantiated to themselves, which is OK as the 
    * bound type variables of a child of a parent are a subset of the bound type 
    * variables of the parent. Example: consider
    *    val (Id,Id') = (fn x => x, fn y => y)
    * This is compiled to something like
    *    LET v192: 
    *        FORALL(a17, a16).(('a16->'a16), ('a17->'a17)) = 
    *           PRIM(RECORDprim, [FN v201: 'a16. v201:(),FN v202: 'a17. v202:()])
    *    IN  LET v193: 
    *          FORALL'a16.('a16->'a16) = 
    *            PRIM(SELECTprim(0), [v192:('a17,'a16)])
    *        IN  LET v194: 
    *              FORALL'a17.('a17->'a17) = 
    *                PRIM(SELECTprim(1), [v192:('a17,'a16)])
    *            IN  ....
    * That is, first a root variable is bound to the expression and then the
    * pattern matching is performed (this code is generated by compileDecTree).
    * When we refer to the parent (the root v192 in this case) to generate the
    * code PRIM(SELECTprim(0), [v192:('a17,'a16)]), we set the instances of the 
    * parent ('a17,'a16) equal to the bound variables of the type scheme for the 
    * parent. This works since the type variables and the type recorded for 
    * label 1 (corresponding to Id) in the pattern of the value binding is
    * 'a16, respectively ('a16->'a16). So this code only works if the type information
    * is not alpha converted!
    *
    * -- Lars.
    *)

    and compileDecTree env (tree,
                            compiler: (int * CE.CEnv) -> LambdaExp,
                            failure,
                            poly 
			    ): LambdaExp =
      case tree
        of LAB_DECOMPOSE{bind, parent, lab, child, info} =>
          let 
	    val info = TypeInfo.normalise info
            fun whichLab info: int =
              case info of
                TypeInfo.LAB_INFO{index,...} =>  index 
              | _ => die "whichLab"
            fun labType info : (TyVar list * StatObject.Type) =
              case info of
                TypeInfo.LAB_INFO{tyvars,Type,...} => (tyvars,Type)
              | _ => die "labType"
	    val (tyvars',tau') = compileTypeScheme (labType info)
	    val env' = CE.declareLvar(bind,map TYVARtype tyvars',env) 
	    val exp' = compileDecTree env' (child,compiler,failure,poly)
	  in (if poly then (polyLet tyvars') else monoLet)
	     ((bind,tau',PRIM(SELECTprim (whichLab info),
			      [VAR{lvar=parent,
				   instances=CE.lookupLvar env parent}])),
	      exp')
          end
         | CON_DECOMPOSE{bind, parent, child,info} =>
	  let val info = TypeInfo.normalise info
	      val (sigma, longcon, instances) =
                 case info 
		   of TypeInfo.CON_INFO{tyvars,Type,longid,instances,...} => 
		    ((tyvars,Type),longid,instances)
		    | _ => die "compileDecTree(CON_DECOMPOSE...)"
	      fun convert_sigma(tyvars,tau) =
		let fun mem [] tv = false
		      | mem (tv'::tvs) tv = TyVar.eq (tv,tv') orelse mem tvs tv 
		    fun NoSome (SOME x) = x
		      | NoSome NONE = die "compileDecTree(CON_DECOMPOSE..): wrong type info 1"
		in
		  case (NoSome o Type.un_FunType o NoSome o Type.to_FunType) tau 
		    of (tau1,_) => (List.all (mem (Type.tyvars tau1)) tyvars, tau1)
		end

(*TODO 18/12/1997 17:15. tho.
 convert_sigma tager et sigma, som best�r af en piltype,
 og returnerer s� at sige sigmaet for argumenttypen.  Alt
 besv�ret kommer af, at listen af bundne tyvar'er skal trimmes.

 Hvorfor er min kode ikke lige s� kompliceret (med convert_sigma, polyLet
 etc.)? Fordi jeg ikke laver s� mange let'er; jeg laver koden `#1 (#2 obj)',
 hvor birkeboy laver koden `let v1 = #2 obj in let v2 = #1 v1 in ...'.  Men
 det skal jeg nok ogs� g�re senere for at undg� at samme v�rdi pilles frem
 flere gange.*)

	  in case lookupLongid env longcon (OTHER "CON_DECOMPOSE")
	       of CE.CON(con,tvs,_,il,it) =>
		 let val (tyvars,tau) = convert_sigma sigma
		     val instances' = map compileType instances
		     val tyvars = map compileTyVar tyvars
		     val tau = compileType tau
		     val env' = CE.declareLvar(bind,map TYVARtype tyvars,env)
		     val exp' =  compileDecTree env' (child,compiler,failure,poly)
		     val S = CE.mk_subst (fn () => "CompileDec.CON_DECOMPOSE.CON") (tvs,instances')
		     val il' = CE.on_il(S, il)
		     val il'' = CE.apply_it(it,il')
		 in (if poly then (polyLet tyvars) else monoLet)
		    ((bind,tau,PRIM(DECONprim{con=con, instances=il''},
				    [VAR{lvar=parent,
					 instances=CE.lookupLvar env parent}])),
		     exp')
		 end
		| CE.REF => 
		 (case instances
		    of [instance] =>                            
		      let val (tyvars,tau) = convert_sigma sigma    (* For deref the instance is the *)
			  val instance' = compileType instance      (* instantiated argument type. *)
			  val tyvars = map compileTyVar tyvars
			  val tau = compileType tau
			  val env' = CE.declareLvar(bind,map TYVARtype tyvars,env)
			  val exp' = compileDecTree env' (child,compiler,failure,poly)
		      in (if poly then polyLet tyvars else monoLet)
			((bind,tau,PRIM(DEREFprim{instance=CONStype([instance'],TyName.tyName_REF)},
					[VAR{lvar=parent,
					     instances=CE.lookupLvar env parent}])),
			 exp')
		      end
		     | _ => die "compileDecTree.CON_DECOMPOSE.wrong number of instances")
		| _ => die "compileDecTree.CON_DECOMPOSE.not CON or REF"
	  end

         | EXCON_DECOMPOSE{bind, parent, child,info} =>
             let
	       val info = TypeInfo.normalise info
               val (Type,longexcon) =
                 case info 
		   of TypeInfo.EXCON_INFO{Type,longid} => (Type,longid)
		    | _ => die "compileDecTree(CON_DECOMPOSE...)"
               val env' = CE.declareLvar(bind,[],env)
               val tau = compileType (domType Type)
	       val exp' = compileDecTree env' (child, compiler, failure,poly)
	     in (if poly then (polyLet []) else monoLet) 
                       (* Could simply use monoLet, but we would like it to be the 
                        * case that all variables bound in value bindings in SML
                        * are compiled to LET-bindings in the lambda language
                        * (to keep it simple to remember)
                        *)
	       ((bind,tau,PRIM(DEEXCONprim (#1(lookupLongexcon env longexcon (OTHER "compileDecTree.EXCON_DECOMPOSE"))),
			       [VAR{lvar=parent,instances=[]}])),
 	        	                 (* instances = [] since the type of the 
                                          * parent must be 'exn' *)
		exp')
             end

         | CON_SWITCH{arg, selections, wildcard} =>
             (case (FinMap.list selections, wildcard)
		of ([(longcon,(ti,tree))], NONE) => compileDecTree env (tree,compiler,failure,poly)

	         | (selections, _) =>
		  let val selections' = map (fn (longcon,(ti,tree)) => 
					     let val e' = compileDecTree env (tree,compiler,failure,poly)
					     in (lookupLongcon env longcon (OTHER "compileDecTree"), e')
					     end) selections
		      val wildcardOpt' = compileDecTreeOpt env (wildcard,compiler,failure,poly)
		  in SWITCH_C(SWITCH(VAR{lvar=arg,instances=CE.lookupLvar env arg},
				     selections',wildcardOpt'))
		  end)

         | SCON_SWITCH{arg, selections, wildcard} =>
             compileSconSwitch env (arg, selections, wildcard, compiler, failure,poly)

         | EXCON_SWITCH{arg, selections, wildcard} =>
             let val selections' = 
	           map (fn (longexcon,tree) =>
			let val e' = compileDecTree env (tree,compiler,failure,poly)
			in (#1(lookupLongexcon env longexcon (OTHER "CompileDecTree.EXCON_SWITCH")),e')
			end) selections
		 val wildcard' = compileDecTree env (wildcard,compiler,failure,poly)
	     in SWITCH_E(SWITCH(VAR{lvar=arg,instances=[]},
                                    (* instances = [] since the type of arg must
                                     * be 'exn'
                                     *)
				selections',SOME wildcard'))
	     end

         | END{ruleNum, environment} => compiler(ruleNum, environment)
         | FAIL => failure

			      and compileDecTreeOpt env (NONE, _, _,_) = NONE
      | compileDecTreeOpt env (SOME t, compiler, failure,poly) =
      SOME(compileDecTree env (t,compiler,failure,poly))
*)


  (* -----------------------------------------------------
   * Modules compilation
   * ----------------------------------------------------- *)

  local 
    open TopdecGrammar         
	   
    fun comp_strexp(ce,strexp) =
      case strexp
	of STRUCTstrexp(info,strdec) => comp_strdec(ce,strdec)
	 | LONGSTRIDstrexp(info,longstrid) => (lookup_longstrid ce longstrid, fn x => x)
	 | TRANSPARENT_CONSTRAINTstrexp(info, strexp, _) =>
	  let val (ce1,f) = comp_strexp(ce,strexp)
	      val E = case to_TypeInfo info
			of SOME (ElabInfo.TypeInfo.TRANS_CONSTRAINT_INFO E) => E
			 | _ => die "comp_strexp.TRANSPARENT_CONSTRAINTstrexp.no env info"
	      val ce2 = CE.constrain(ce1,E)
	  in (ce2, f)
	  end
	 | OPAQUE_CONSTRAINTstrexp(info, strexp, _) => die "OPAQUE_CONSTRAINTstrexp.not impl"
	 | APPstrexp _ => die "APPstrexp.not supported by compiler"
	 | LETstrexp(info, strdec, strexp) =>
	  let val (ce1, f1) = comp_strdec(ce,strdec)
	      val (ce2, f2) = comp_strexp(CE.plus(ce,ce1), strexp)
	  in (ce2, f1 o f2)
	  end

    and comp_strdec(ce: CE.CEnv, strdec: strdec) =
      case strdec
	of DECstrdec(info, dec) => compileDec ce (false,dec)
	     (*topLevel=false: we always want the warnings, since this is
	      a compiler - not a top-level loop. - Martin *)
	 | STRUCTUREstrdec(info, strbind) => comp_strbind(ce,strbind)
	 | LOCALstrdec(info, strdec1, strdec2) =>
	  let val (ce1, f1) = comp_strdec(ce,strdec1)
	      val (ce2, f2) = comp_strdec(CE.plus(ce,ce1), strdec2)
	  in (ce2, f1 o f2)
	  end
	 | EMPTYstrdec info => (CE.emptyCEnv, fn x => x)
	 | SEQstrdec(info, strdec1, strdec2) =>
	  let val (ce1, f1) = comp_strdec(ce,strdec1)
	      val (ce2, f2) = comp_strdec(CE.plus(ce,ce1), strdec2)
	  in (CE.plus(ce1,ce2), f1 o f2)
	  end

    and comp_strbind(ce,STRBIND(info,strid,strexp,strbind_opt)) =
      let val (ce1, f1) = comp_strexp(ce,strexp)
	  val ce1 = CE.declare_strid(strid,ce1,CE.emptyCEnv) 
      in case strbind_opt
	   of SOME strbind' => 
	     let val (ce2, f2) = comp_strbind(ce,strbind')
	     in (CE.plus(ce1,ce2), f1 o f2)
	     end
	    | NONE => (ce1, f1)
      end 

  in (*local*)

    fun comp_strdecs(ce,[]) = (CE.emptyCEnv, fn x => x)
      | comp_strdecs(ce, strdec::strdecs) =
      let val (ce1,f1) = comp_strdec(ce,strdec)
	  val (ce2,f2) = comp_strdecs(CE.plus(ce,ce1),strdecs)
      in (CE.plus(ce1,ce2), f1 o f2)
      end

  end (*local*)


  (* -----------------------------------------------------
   * Main compilation function
   * ----------------------------------------------------- *)

  type strdec = TopdecGrammar.strdec
  fun compileStrdecs env strdecs = 
    let val _ = DatBinds.reset()
        val _ = TV.reset()
        val (env1, f1) = comp_strdecs(env, strdecs)

        (* Determine the scope of the declaration. Those lvars and
	 * excons which are declared by the declarations are those
	 * that appear in env1 but not in env. *)

	val typed_declared_lvars = 
              (* we associated the declared_lvars with dummy type schemes;
	       * the real type schemes are put in later; actually, now we 
	       * could put them in... *)
	  let val lvars_env = CE.lvarsOfCEnv env
	      val lvars_decl = 
		List.foldL (fn lv1 => fn lvs =>
			    if List.exists (fn lv => Lvars.eq(lv,lv1)) lvars_env then lvs
			    else lv1::lvs) [] (CE.lvarsOfCEnv env1)
	      val alpha = fresh_tyvar()
	  in map (fn lv => {lvar=lv,tyvars = [alpha],Type=TYVARtype alpha})    (* forall alpha. alpha *)
	     lvars_decl
	  end

       val declared_excons : (Excon.excon * Type option) list =
	 let val excons_env = CompilerEnv.exconsOfCEnv env
	     val excons_decl = 
	       List.foldL (fn ex1 => fn exs =>
			   if List.exists (fn ex => Excon.eq(ex,ex1)) excons_env then exs
			   else ex1::exs) [] (CE.exconsOfCEnv env1)
	 in map (fn excon => (excon, NONE)) excons_decl  (*dummy-NONE*)
	 end

       val scope = FRAME{declared_lvars=typed_declared_lvars,
			 declared_excons=declared_excons}

       (* Build the lambda expression *)
       val lamb = f1 scope

       (* Then we can extract the datbinds *)
       val datbindss = DatBinds.extract()
       val pgm = PGM(DATBINDS datbindss, lamb)
    in (env1, pgm)
    end

  type TypeScheme = StatObject.TypeScheme
  type tyvar = LambdaExp.tyvar
  val compileTypeScheme : TypeScheme -> tyvar list * Type = fn sigma =>
    compileTypeScheme (TypeScheme.to_TyVars_and_Type sigma)

  val _ = CE.set_compileTypeScheme compileTypeScheme   (* MEGA HACK - Martin *)
  val _ = CE.set_normalize_sigma normalize_sigma   (* Another one; Mads *)

  fun reset () = () 

  end;
