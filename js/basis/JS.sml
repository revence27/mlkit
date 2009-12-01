signature JS = 
sig
  (* dom *)
  eqtype doc 
  eqtype elem
  val document        : doc
  val documentElement : doc -> elem
  val getElementById  : doc -> string -> elem option
  val parent          : elem -> elem option
  val firstChild      : elem -> elem option
  val lastChild       : elem -> elem option
  val nextSibling     : elem -> elem option
  val previousSibling : elem -> elem option
  val innerHTML       : elem -> string -> unit
  val value           : elem -> string
  val setAttribute    : elem -> string -> string -> unit
  val removeAttribute : elem -> string -> unit
  val createElement   : string -> elem
  val createTextNode  : string -> elem
  val createFragment  : unit -> elem
  val appendChild     : elem -> elem -> unit
  val removeChild     : elem -> elem -> unit
  val replaceChild    : elem -> elem -> elem -> unit

  (* events *)
  datatype eventType = onclick | onchange | onkeypress 
                     | onkeyup | onmouseover | onmouseout
  val installEventHandler : elem -> eventType -> (unit -> bool) -> unit
  val getEventHandler     : elem -> eventType -> (unit -> bool) option
  val onMouseMove         : doc -> (int*int -> unit) -> unit

  (* timers *)
  type intervalId
  val setInterval     : int -> (unit -> unit) -> intervalId
  val clearInterval   : intervalId -> unit

  type timeoutId
  val setTimeout      : int -> (unit -> unit) -> timeoutId
  val clearTimeout    : timeoutId -> unit

  (* styles *)
  val setStyle        : elem -> string * string -> unit

  structure XMLHttpRequest : sig
    type req
    val new              : unit -> req
    val openn            : req -> {method: string, url: string, async: bool} -> unit
    val setRequestHeader : req -> string * string -> unit
    val send             : req -> string option -> unit
    val state            : req -> int        (* 0,1,2,3,4 *)
    val status           : req -> int option (* 200, 404, ... *)
    val onStateChange    : req -> (unit -> unit) -> unit
    val response         : req -> string option
    val abort            : req -> unit
  end 

  val random             : unit -> real
(*
  val rpc : 'a T -> 'b T -> {url: string, method: string} 
	    -> 'a -> 'b

  val rpcAsync : 'a T -> 'b T -> {url: string, method: string} 
	    -> ('b -> unit) -> 'a -> unit
*)
end

(*
  [parent e] returns SOME p, if p is the parent of e. Returns NONE if
  e has no parent.

  [appendChild e child] appends child to e.

  [removeChild e child] removes child from e.

  [replaceChild e new old] replaces old child from e with new child.

  [random()] returns a random real in the interval [0.0,1.0[.
*)
