(* Compiler for 100 *)
(* Compile by mosmlc -c Compiler.sml *)

structure Compiler :> Compiler =
struct

  (* Use "raise Error (message,position)" for error messages *)
  exception Error of string*(int*int)

  (* Name generator.  Call with, e.g., t1 = "tmp"^newName () *)
  val counter = ref 0

  fun newName () = (counter := !counter + 1;
                  "_" ^ Int.toString (!counter)^ "_")

  (* Number to text with spim-compatible sign symbol *)
  fun makeConst n = if n>=0 then Int.toString n
                    else "-" ^ Int.toString (~n)

  fun lookup x [] = NONE
    | lookup x ((y,v)::table) = if x=y then SOME v else lookup x table

  fun isIn x [] = false
    | isIn x (y::ys) = x=y orelse isIn x ys

  (* link register *)
  val RA = "31"
  (* Register for stack pointer *)
  val SP = "29"
  (* Register for heap pointer *)
  val HP = "28"
  (* Register for frame pointer *)
  val FP = "25"

  (* Suggested register division *)
  val maxCaller = 15   (* highest caller-saves register *)
  val maxReg = 24      (* highest allocatable register *)

  datatype Location = Reg of string | Mem of string

  (* compile expression *)
  fun compileExp e vtable ftable place =
    case e of
      S100.NumConst (n,pos) =>
        if n<32768 then
	  (Type.Int,[Mips.LI (place, makeConst n)])
	else
	  (Type.Int,
	   [Mips.LUI (place, makeConst (n div 65536)),
	   Mips.ORI (place, place, makeConst (n mod 65536))])
    | S100.CharConst (c,pos) =>
	  (Type.Int,[Mips.LI (place, makeConst (ord c))])
    | S100.StringConst (s,pos) =>
        let
	  val len = String.size s
	  val len2 = 4*((len+4) div 4)
	  val k = "_stringConst_"^newName()
	in
	  (Type.Ref Type.Char,
	   [Mips.MOVE (place, HP),
	    Mips.ADDI (HP,HP,Int.toString len2)]
	   @ List.concat
	       (List.tabulate
		  (len,
		   fn i => [Mips.ORI
			      (k,"0","'"^Char.toCString (String.sub (s,i))^"'"),
			    Mips.SB (k,place,Int.toString i)]))
	   @ [Mips.SB ("0",place,Int.toString len)]
	  )
	end
    | S100.LV lval =>
        let
	  val (code,ty,loc) = compileLval lval vtable ftable
	in
	  case (ty,loc) of
	    (Type.Int, Reg x) =>
	      (Type.Int,
	       code @ [Mips.MOVE (place,x)])
	  | (Type.Char, Reg x) =>
	      (Type.Int,
	       code @ [Mips.MOVE (place,x)])
	  | (Type.Ref Type.Int, Reg x) =>
	      (Type.Ref Type.Int,
	       code @ [Mips.MOVE (place,x)])
	  | (Type.Ref Type.Char, Reg x) =>
	      (Type.Ref Type.Char,
	       code @ [Mips.MOVE (place,x)])
	  | (Type.Int, Mem x) =>
	      (Type.Int,
	       code @ [Mips.LW (place,x,"0")])
	  | (Type.Char, Mem x) =>
	      (Type.Int,
	       code @ [Mips.LB (place,x,"0")])
	  | _ => raise Error ("Bad lval",(0,0))
	end
    | S100.Assign (lval,e,p) =>
        let
          val t = "_assign_"^newName()
	  val (code0,ty,loc) = compileLval lval vtable ftable
	  val (_,code1) = compileExp e vtable ftable t
	in
	  case (ty,loc) of
	    (Type.Int, Reg x) =>
	      (Type.Int,
	       code0 @ code1 @ [Mips.MOVE (x,t), Mips.MOVE (place,t)])
	  | (Type.Char, Reg x) =>
	      (Type.Int,
	       code0 @ code1 @ [Mips.ANDI (x,t,"255"), Mips.MOVE (place,t)])
	  | (Type.Ref Type.Int, Reg x) =>
	      (Type.Ref Type.Int,
	       code0 @ code1 @ [Mips.MOVE (x,t), Mips.MOVE (place,t)])
	  | (Type.Ref Type.Char, Reg x) =>
	      (Type.Ref Type.Char,
	       code0 @ code1 @ [Mips.MOVE (x,t), Mips.MOVE (place,t)])
	  | (Type.Int, Mem x) =>
	      (Type.Int,
	       code0 @ code1 @ [Mips.SW (t,x,"0"), Mips.MOVE (place, t)])
	  | (Type.Char, Mem x) =>
	      (Type.Int,
	       code0 @ code1 @ [Mips.SB (t,x,"0"), Mips.MOVE (place, t)])
	  | _ => raise Error ("Bad lval",(0,0))
	end
    | S100.Plus (e1,e2,pos) =>
        let
	  val t1 = "_plus1_"^newName()
	  val t2 = "_plus2_"^newName()
          val (ty1,code1) = compileExp e1 vtable ftable t1
          val (ty2,code2) = compileExp e2 vtable ftable t2
	in
	  case (ty1,ty2) of
	    (Type.Ref Type.Int, Type.Int) =>
	      (Type.Ref Type.Int,
	       code1 @ code2 @ [Mips.SLL (t2,t2,"2"), Mips.ADD (place,t1,t2)])
	  | (Type.Int, Type.Ref Type.Int) =>
	      (Type.Ref Type.Int,
	       code1 @ code2 @ [Mips.SLL (t1,t1,"2"), Mips.ADD (place,t1,t2)])
	  | (Type.Ref Type.Char, Type.Int) =>
	      (Type.Ref Type.Char,
	       code1 @ code2 @ [Mips.ADD (place,t1,t2)])
	  | (Type.Int, Type.Ref Type.Char) =>
	      (Type.Ref Type.Char,
	       code1 @ code2 @ [Mips.ADD (place,t1,t2)])
	  | _  (* (Int, Int) *) =>
	      (Type.Int,
	       code1 @ code2 @ [Mips.ADD (place,t1,t2)])
	end
    | S100.Minus (e1,e2,pos) =>
        let
	  val t1 = "_minus1_"^newName()
	  val t2 = "_minus2_"^newName()
          val (ty1,code1) = compileExp e1 vtable ftable t1
          val (ty2,code2) = compileExp e2 vtable ftable t2
	in
	  case (ty1,ty2) of
	    (Type.Ref Type.Int, Type.Int) =>
	      (Type.Ref Type.Int,
	       code1 @ code2 @ [Mips.SLL (t2,t2,"2"), Mips.SUB (place,t1,t2)])
	  | (Type.Ref Type.Char, Type.Int) =>
	      (Type.Ref Type.Char,
	       code1 @ code2 @ [Mips.SUB (place,t1,t2)])
	  | (Type.Ref Type.Int, Type.Ref Type.Int) =>
	      (Type.Int,
	       code1 @ code2 @
	       [Mips.SUB (place,t1,t2), Mips.SRA (place,place,"2")])
	  | (Type.Ref Type.Char, Type.Ref Type.Char) =>
	      (Type.Int,
	       code1 @ code2 @ [Mips.SUB (place,t1,t2)])
	  | _ (* (Int, Int) *) =>
	      (Type.Int,
	       code1 @ code2 @ [Mips.SUB (place,t1,t2)])
	end
    | S100.Less (e1,e2,pos) =>
        let
	  val t1 = "_less1_"^newName()
	  val t2 = "_less2_"^newName()
          val (_,code1) = compileExp e1 vtable ftable t1
          val (_,code2) = compileExp e2 vtable ftable t2
	in
	  (Type.Int, code1 @ code2 @ [Mips.SLT (place,t1,t2)])
	end
    | S100.Equal (e1,e2,pos) =>
        let
	  val t1 = "_less1_"^newName()
	  val t2 = "_less2_"^newName()
	  val t3 = "_less2_"^newName()
	  val t4 = "_less2_"^newName()
          val (_,code1) = compileExp e1 vtable ftable t1
          val (_,code2) = compileExp e2 vtable ftable t2
	in
	  (Type.Int,
	   code1 @ code2 @
	   [Mips.SLT (t3,t1,t2), Mips.SLT (t4,t2,t1),
	    Mips.OR (t3,t3,t4), Mips.XORI (place, t3, "1")])
	end
    | S100.Call (f,es,pos) =>
	let
	  val rTy = case lookup f ftable of
		      SOME (_,t) => t
		    | NONE => raise Error ("unknown function "^f,pos)
	  val (code1,args) = compileExps es vtable ftable
	  fun moveArgs [] r = ([],[],0)
	    | moveArgs (arg::args) r =
	        let
		  val (code,parRegs,stackSpace) = moveArgs args (r+1)
		  val rname = makeConst r
		in
	          if r<=maxCaller then
		    (Mips.MOVE (rname,arg) :: code,
		     rname :: parRegs,
		     stackSpace)
		  else
		    (Mips.SW (arg,SP,makeConst stackSpace) :: code,
		     parRegs,
		     stackSpace + 4)
		end
	  val (moveCode, parRegs, stackSpace) = moveArgs args 2
	in
	  (if rTy = Type.Char then Type.Int else rTy,
	   if stackSpace>0 then
	     [Mips.ADDI (SP,SP,makeConst (~stackSpace))]
	     @ code1 @ moveCode @
	     [Mips.JAL (f, parRegs),
	      Mips.MOVE (place,"2"),
	      Mips.ADDI (SP,SP,makeConst stackSpace)]
	   else
	     code1 @ moveCode @
	     [Mips.JAL (f, parRegs),
	      Mips.MOVE (place,"2")])
	end

  and compileExps [] vtable ftable = ([], [])
    | compileExps (e::es) vtable ftable =
        let
	  val t1 = "_exps_"^newName()
          val (_,code1) = compileExp e vtable ftable t1
	  val (code2, regs) = compileExps es vtable ftable
	in
	  (code1 @ code2, t1 :: regs)
	end

  and compileLval lval vtable ftable =
    case lval of
      S100.Var (x,p) =>
        (case lookup x vtable of
	   SOME (ty,y) => ([],ty,Reg y)
	 | NONE => raise Error ("Unknown variable "^x,p))
    | S100.Deref (x,p) =>
        (case lookup x vtable of
	   SOME (Type.Ref t, y) => ([],t, Mem y)
	 | SOME _ => raise Error (x^" is not a referece variable",p)
	 | NONE => raise Error ("Unknown variable "^x,p))
    | S100.Lookup (x,e,p) =>
        let
	  val t1 = "_index_"^newName()
	  val (_,code0) = compileExp e vtable ftable t1
	in
          case lookup x vtable of
	    SOME (Type.Ref Type.Int, y) =>
	      let
		val t2 = "_lookup_"^newName()
		val code1 = [Mips.SLL (t2,t1,"2"), (* scale index *)
			     Mips.ADD (t2,t2,y)]   (* add base *)
	      in
		(code0 @ code1, Type.Int, Mem t2)
	      end
	  | SOME (Type.Ref Type.Char, y) =>
	      let
		val t2 = "_lookup_"^newName()
		val code1 = [Mips.ADD (t2,t1,y)]   (* add base *)
	      in
		(code0 @ code1, Type.Char, Mem t2)
	      end
	  | SOME _ => raise Error (x^" is not a referece variable",p)
	  | NONE => raise Error ("Unknown variable "^x,p)
	end

  fun compileStat s vtable ftable exitLabel catchLabel catchVar =
    case s of
      S100.EX e => #2 (compileExp e vtable ftable "0")
    | S100.If (e,s1,p) =>
        let
	  val t = "_if_"^newName()
	  val l1 = "_endif_"^newName()
	  val (_,code0) = compileExp e vtable ftable t
	  val code1 = compileStat s1 vtable ftable exitLabel catchLabel catchVar
	in
	  code0 @ [Mips.BEQ (t,"0",l1)] @ code1 @ [Mips.LABEL l1]
	end
    | S100.IfElse (e,s1,s2,p) =>
        let
	  val t = "_if_"^newName()
	  val l1 = "_else_"^newName()
	  val l2 = "_endif_"^newName()
	  val (_,code0) = compileExp e vtable ftable t
	  val code1 = compileStat s1 vtable ftable exitLabel catchLabel catchVar
	  val code2 = compileStat s2 vtable ftable exitLabel catchLabel catchVar
	in
	  code0 @ [Mips.BEQ (t,"0",l1)] @ code1
	  @ [Mips.J l2, Mips.LABEL l1] @ code2 @ [Mips.LABEL l2]
	end
    | S100.While (e,s1,p) =>
        let
	  val t = "_while_"^newName()
	  val l1 = "_wentry_"^newName()
	  val l2 = "_wexit_"^newName()
	  val (_,code0) = compileExp e vtable ftable t
	  val code1 = compileStat s1 vtable ftable exitLabel catchLabel catchVar
	in
	  [Mips.LABEL l1] @ code0 @ [Mips.BEQ (t,"0",l2)]
	  @ code1 @ [Mips.J l1, Mips.LABEL l2]
	end
    | S100.Return (e,p) =>
        let
	  val t = "_return_"^newName()
	  val (_,code0) = compileExp e vtable ftable t
	in
	  code0 @ [Mips.MOVE ("2",t), Mips.J exitLabel]
	end
    | S100.Block (decs, stats, p) =>
        let
	  fun extend [] vtable = vtable
	    | extend ((t,ss)::ds) vtable =
	        extend1 ss (Type.convertType t) ds vtable
	  and extend1 [] t ds vtable = extend ds vtable
	    | extend1 (s::ss) t ds vtable =
	       (case s of
		  S100.Val (x,p) => (x,(t, newName()))
		| S100.Ref (x,p) => (x,(Type.Ref t,newName())))
	       :: extend1 ss t ds vtable
	  val vtable1 = extend decs vtable
	in
	  List.concat
	      (List.map (fn s => compileStat s vtable1 ftable exitLabel catchLabel catchVar) stats)
	end

    | S100.Throw (exp, p) =>
      let
        val (_,exCode) = compileExp exp vtable ftable catchVar
      in
        exCode @
        [Mips.OR("4","0", catchVar),
         Mips.J catchLabel ]
      end
    
    | S100.TryCatch (s1, sid, s2, p)  =>
      (* TODO: FIXME: Make me work across function calls.  *)
        let
          val l1 = "_tryentry_"^newName()
	  val l2 = "_catchentry_"^newName()
          val l3 = "_catchexit_"^newName()
          val exName = (Type.getName(sid))
          val vtable1 = [(exName,(Type.Int,catchVar))] @ vtable

          val s1code =  List.concat
              (map (fn s => compileStat s vtable ftable exitLabel l2 catchVar) s1)
          val s2code = compileStat s2 vtable1 ftable exitLabel catchLabel exName
        in
          [Mips.LABEL l1] @
          s1code @
          [Mips.J l3,
           Mips.LABEL l2] @
          s2code @
          [Mips.LABEL l3]
        end

  (* code for saving and restoring callee-saves registers *)
  fun stackSave currentReg maxReg savecode restorecode offset =
    if currentReg > maxReg
    then (savecode, restorecode, offset)  (* done *)
    else stackSave (currentReg+1)
                   maxReg
                   (Mips.SW (makeConst currentReg,
                                 SP,
                                 makeConst offset)
                    :: savecode) (* save register *)
                   (Mips.LW (makeConst currentReg,
                                 SP,
                                 makeConst offset)
                    :: restorecode) (* restore register *)
                   (offset+4) (* adjust offset *)


  (* compile function declaration *)
  and compileFun ftable (typ, sf, args, body, (line,col)) =
        let
	  val fname = Type.getName sf
	  val rty = Type.getType typ sf
	  fun moveArgs [] r = ([], [], 0)
	    | moveArgs ((t,ss)::ds) r =
	        moveArgs1 ss (Type.convertType t) ds r
	  and moveArgs1 [] t ds r = moveArgs ds r
	    | moveArgs1 (s::ss) t ds r =
	       let
		 val y = newName ()
		 val (x,ty,loc) = (case s of
			         S100.Val (x,p) => (x, t, x^y)
			       | S100.Ref (x,p) => (x, Type.Ref t, x^y))
		 val rname = Int.toString r
		 val (code, vtable, stackSpace) = moveArgs1 ss t ds (r+1)
	       in
		 if ty = Type.Char then
		   if r<=maxCaller then
		     (Mips.ANDI (loc, rname, "255") :: code,
		      (x,(ty,loc)) :: vtable,
		      stackSpace)
		   else
		     (Mips.LB (loc, FP, makeConst stackSpace) :: code,
		      (x,(ty,loc)) :: vtable,
		      stackSpace + 4)
		 else
		   if r<=maxCaller then
		     (Mips.MOVE (loc, rname) :: code,
		      (x,(ty,loc)) :: vtable,
		      stackSpace)
		   else
		     (Mips.LW (loc, FP, makeConst stackSpace) :: code,
		      (x,(ty,loc)) :: vtable,
		      stackSpace + 4)
	       end
	  val (parcode,vtable,stackParams) (* move parameters to arguments *)
            = moveArgs args 2

          val catchVar = "_ex_"^newName()
          val body = compileStat body vtable ftable (fname ^ "_exit") "unhandled" catchVar


          val (body1, _, maxr,spilled)  (* call register allocator *)
            = RegAlloc.registerAlloc
                (parcode @ body) [] 2 maxCaller maxReg 0
          val (savecode, restorecode, offset) = (* save/restore callee-saves *)
                stackSave (maxCaller+1) (maxr+1) [] [] (4*spilled)
		(* save one extra callee-saves register for saving SP *)
	  val ctext = if spilled>0
		  then "Spill of "^makeConst spilled ^ " variables occurred"
		  else ""
        in
            [Mips.COMMENT ctext,
             Mips.LABEL fname]  (* function label *)
	  @ (if stackParams>0 then [Mips.MOVE (FP,SP)] else [])
 	  @ [Mips.ADDI (SP,SP,makeConst (~4-offset)), (* move SP down *)
             Mips.SW (RA, SP, makeConst offset)] (* save return address *)
          @ savecode  (* save callee-saves registers *)
          @ body1  (* code for function body *)
	  @ [Mips.LABEL (fname^"_exit")] (* exit label *)
	  @ (if rty=Type.Char then [Mips.ANDI ("2","2","255")] else [])
          @ restorecode  (* restore callee-saves registers *)
          @ [Mips.LW (RA, SP, makeConst offset), (* restore return addr *)
             Mips.ADDI (SP,SP,makeConst (offset+4)), (* move SP up *)
             Mips.JR (RA, [])] (* return *)
        end

  (* compile program *)
  fun compile funs =
    let
      val ftable =
	  Type.getFuns funs [("unhandled",([Type.Int],Type.Int)),
                             ("walloc",([Type.Int],Type.Ref Type.Int)),
			     ("balloc",([Type.Int],Type.Ref Type.Char)),
			     ("getint",([],Type.Int)),
			     ("getstring",([Type.Int],Type.Ref Type.Char)),
			     ("putint",([Type.Int],Type.Int)),
			     ("putstring",
			      ([Type.Ref Type.Char],Type.Ref Type.Char))]
      val funsCode = List.concat (List.map (compileFun ftable) funs)
    in
      [Mips.TEXT "0x00400000",
       Mips.GLOBL "main",
       Mips.LA (HP, "_heap_")]    (* initialise heap pointer *)
      @ [Mips.JAL ("main",[]),    (* run program *)
	 Mips.LI ("2","10"),      (* syscall control = 10 *)
         Mips.SYSCALL]            (* exit *)
      @ funsCode		  (* code for functions *)

      @ [(* code for unhandles exceptions
          * Tager exception nummeret i register 4.
          *)
         Mips.LABEL "unhandled",
         Mips.ADDI(SP,SP,"-8"),
         Mips.SW(RA,SP,"0"),
         Mips.SW("4",SP,"4"),
         Mips.ORI("2",HP,"0"),
         Mips.ADDI(HP,HP,"22"),
         Mips.ORI("3","0","'U'"),
         Mips.SB("3","2","0"),
         Mips.ORI("3","0","'n'"),
         Mips.SB("3","2","1"),
         Mips.ORI("3","0","'c'"),
         Mips.SB("3","2","2"),
         Mips.ORI("3","0","'a'"),
         Mips.SB("3","2","3"),
         Mips.ORI("3","0","'u'"),
         Mips.SB("3","2","4"),
         Mips.ORI("3","0","'g'"),
         Mips.SB("3","2","5"),
         Mips.ORI("3","0","'h'"),
         Mips.SB("3","2","6"),
         Mips.ORI("3","0","'t'"),
         Mips.SB("3","2","7"),
         Mips.ORI("3","0","' '"),
         Mips.SB("3","2","8"),
         Mips.ORI("3","0","'e'"),
         Mips.SB("3","2","9"),
         Mips.ORI("3","0","'x'"),
         Mips.SB("3","2","10"),
         Mips.ORI("3","0","'c'"),
         Mips.SB("3","2","11"),
         Mips.ORI("3","0","'e'"),
         Mips.SB("3","2","12"),
         Mips.ORI("3","0","'p'"),
         Mips.SB("3","2","13"),
         Mips.ORI("3","0","'t'"),
         Mips.SB("3","2","14"),
         Mips.ORI("3","0","'i'"),
         Mips.SB("3","2","15"),
         Mips.ORI("3","0","'o'"),
         Mips.SB("3","2","16"),
         Mips.ORI("3","0","'n'"),
         Mips.SB("3","2","17"),
         Mips.ORI("3","0","':'"),
         Mips.SB("3","2","18"),
         Mips.ORI("3","0","' '"),
         Mips.SB("3","2","19"),
         Mips.SB("0","2","21"), (* insert the nullbyte string terminator *)
         Mips.JAL("putstring",[]),
         Mips.LW("2",SP,"4"),
         Mips.JAL("putint",[]),
         Mips.LW(RA,SP,"0"),
         Mips.ADDI(SP,SP,"8"),
         Mips.LI ("2","10"),      (* syscall control = 10 *)
         Mips.SYSCALL]            (* exit *)
        

      @ [Mips.LABEL "putint",     (* putint function *)
	 Mips.MOVE ("4","2"),
	 Mips.LI ("2","1"),       (* write_int syscall *)
	 Mips.SYSCALL,
	 Mips.LI ("2","4"),       (* writestring syscall *)
	 Mips.LA("4","_cr_"),
	 Mips.SYSCALL,            (* write CR *)
	 Mips.JR (RA,[]),

	 Mips.LABEL "putstring",  (* putstring function *)
	 Mips.MOVE ("4","2"),     (* move string pointer to r4 *)
	 Mips.LI ("2","4"),       (* write_string syscall *)
	 Mips.SYSCALL,
	 Mips.JR (RA,[]),

	 Mips.LABEL "getint",     (* getint function *)
	 Mips.LI ("2","5"),       (* read_int syscall *)
	 Mips.SYSCALL,
	 Mips.JR (RA,[]),

	 Mips.LABEL "walloc",     (* walloc function *)
	 Mips.ADDI(HP,HP,"-1"),   (* word-align HP *)
	 Mips.ORI(HP,HP,"3"),
	 Mips.ADDI(HP,HP,"1"),
	 Mips.SLL("2","2","2"),   (* scale by 4 *)
	 Mips.ADD(HP,HP,"2"),     (* allocate space *)
	 Mips.SUB("2",HP,"2"),    (* return pointer to allocated space *)
	 Mips.JR (RA,[]),

	 Mips.LABEL "balloc",     (* balloc function *)
	 Mips.ADD(HP,HP,"2"),     (* allocate space *)
	 Mips.SUB("2",HP,"2"),    (* return pointer to allocated space *)
	 Mips.JR (RA,[]),

	 Mips.LABEL "getstring",  (* getstring function *)
	 Mips.MOVE("4",HP),       (* allocate at HP *)
         Mips.MOVE("5","2"),      (* N bytes *)
	 Mips.LI ("2","8"),       (* read_string syscall *)
	 Mips.SYSCALL,
	 Mips.MOVE("2",HP),       (* return HP *)
	 Mips.ADD(HP,HP,"5"),     (* increase HP by N *)
	 Mips.JR (RA,[]),

	 Mips.DATA "",
	 Mips.ALIGN "2",
	 Mips.LABEL "_cr_",       (* carriage return string *)
	 Mips.ASCIIZ "\n",
	 Mips.ALIGN "2",

	 Mips.LABEL "_heap_",     (* heap space *)
	 Mips.SPACE "100000"]
    end

end
