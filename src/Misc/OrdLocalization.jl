export OrdLoc, OrdLocElem

###############################################################################
#
#   Declaration types
#   OrdLoc / OrdLocElem
#
###############################################################################

mutable struct OrdLoc{T<:nf_elem} <: Hecke.Ring
   OK::NfAbsOrd{AnticNumberField,T}
   prime::NfAbsOrdIdl{AnticNumberField,T}

   function OrdLoc{T}(OK::NfAbsOrd{AnticNumberField,T}, prime::NfAbsOrdIdl{AnticNumberField,T}, checked::Bool = true, cached::Bool = true) where {T <: nf_elem}
      checked && !isprime(prime) && error("Ideal is not prime")
      if cached && haskey(OrdLocDict, (OK, prime))
         return OrdLocDict[OK, prime]::OrdLoc{T}
      else
         z = new(OK, prime)
         if cached
            OrdLocDict[OK, prime] = z
         end
         return z
      end
   end
end


OrdLocDict = Dict{Tuple{NfAbsOrd{AnticNumberField,nf_elem}, NfAbsOrdIdl{AnticNumberField,nf_elem}}, Hecke.Ring}()

mutable struct OrdLocElem{T<:nf_elem} <: RingElem
   data::T
   parent::OrdLoc{T}

   function OrdLocElem{T}(data::T, par::OrdLoc, checked::Bool = true) where {T <:nf_elem}
      data == zero(parent(data)) && return new{T}(data,par)
      checked && valuation(data, prime(par))<0 && error("No valid element of localization")
      return new{T}(data,par)
   end
end

###############################################################################
#
#   Unsafe operators and functions
#
###############################################################################

add!(c::OrdLocElem, a::OrdLocElem, b::OrdLocElem) = a + b

mul!(c::OrdLocElem, a::OrdLocElem, b::OrdLocElem) = a * b

addeq!(a::OrdLocElem, b::OrdLocElem) = a + b

###############################################################################
#
#   Data type and parent object methods
#
###############################################################################

elem_type(::Type{OrdLoc{T}}) where {T <: nf_elem} = OrdLocElem{T}

parent_type(::Type{OrdLocElem{T}}) where {T <: nf_elem} = OrdLoc{T}

order(L::OrdLoc{T}) where {T <: nf_elem}  = L.OK

order(a::OrdLocElem{T}) where {T <: nf_elem}  = order(parent(a))

nf(L::OrdLoc{T}) where {T <: nf_elem}  = nf(L.OK)::parent_type(T)

nf(a::OrdLocElem{T}) where {T <: nf_elem} = nf(parent(a))

parent(a::OrdLocElem{T})  where {T <: nf_elem} = a.parent

function check_parent(a::OrdLocElem{T}, b::OrdLocElem{T})  where {T <: nf_elem}
    parent(a) != parent(b) && error("Parent objects do not match")
end


###############################################################################
#
#   Basic manipulation
#
###############################################################################

data(a::OrdLocElem{T}) where {T <: nf_elem} = a.data

numerator(a::OrdLocElem{T}) where {T <: nf_elem} = numerator(data(a))

denominator(a::OrdLocElem{T}) where {T <: nf_elem} = denominator(data(a))

prime(L::OrdLoc{T}) where {T <: nf_elem} = L.prime

prime(a::OrdLocElem{T}) where {T <: nf_elem} = prime(parent(a))

zero(L::OrdLoc{T}) where {T <: nf_elem} = L(0)

one(L::OrdLoc{T}) where {T <: nf_elem} = L(1)

iszero(a::OrdLocElem{T}) where {T <: nf_elem} = iszero(data(a))

isone(a::OrdLocElem{T}) where {T <: nf_elem} = isone(data(a))

function in(x::nf_elem, L::OrdLoc)
   iszero(x) ? true :
   return valuation(x,prime(L)) >= 0
end

function isunit(a::OrdLocElem{T})  where {T <: nf_elem}
   iszero(a) ? false :
    return valuation(data(a),prime(a))==0
end

deepcopy_internal(a::OrdLocElem{T}, dict::IdDict) where {T <: nf_elem} = parent(a)(deepcopy(data(a)))

###############################################################################
#
#   AbstractString I/O
#
###############################################################################

function show(io::IO, a::OrdLocElem{T}) where {T <: nf_elem}
   print(io, data(a))
end

function show(io::IO, L::OrdLoc{T}) where {T <: nf_elem}
   print(io, "Localization of ", order(L), " at ", prime(L))
end

needs_parentheses(x::OrdLocElem{T})  where {T <: nf_elem} = needs_parentheses(data(x))

displayed_with_minus_in_front(x::OrdLocElem{T})  where {T <: nf_elem} = displayed_with_minus_in_front(data(x))

show_minus_one(::Type{OrdLocElem{T}}) where {T <: nf_elem} = true

##############################################################################
#
#   Unary operations
#
##############################################################################

function -(a::OrdLocElem{T})  where {T <: nf_elem}
   parent(a)(-data(a))
end

###############################################################################
#
#   Binary operators
#
###############################################################################

function +(a::OrdLocElem{T}, b::OrdLocElem{T})  where {T <: nf_elem}
   check_parent(a,b)
   return parent(a)(data(a) + data(b), false)
end

function -(a::OrdLocElem{T}, b::OrdLocElem{T})  where {T <: nf_elem}
   check_parent(a,b)
   return parent(a)(data(a) - data(b), false)
end

function *(a::OrdLocElem{T}, b::OrdLocElem{T})  where {T <: nf_elem}
   check_parent(a,b)
   return parent(a)(data(a) * data(b), false)
end

###############################################################################
#
#   Comparison
#
###############################################################################

function ==(a::OrdLocElem{T}, b::OrdLocElem{T}) where {T <: nf_elem}
   check_parent(a, b)
   return data(a) == data(b)
end

##############################################################################
#
#  Inversion
#
##############################################################################

@doc Markdown.doc"""
     inv(a::OrdLocElem{T}, checked::Bool = true)  where {T <: nf_elem}
> Returns the inverse element of $a$ if $a$ is a unit.
> If 'checked = false' the invertibility of $a$ is not checked and the corresponding inverse element
> of the numberfield is returned.
"""
function inv(a::OrdLocElem{T}, checked::Bool = true)  where {T <: nf_elem}
   checked && !isunit(a) && error("$a not invertible in given localization")
   return parent(a)(inv(data(a)), false)
end

##############################################################################
#
#  Exact division
#
##############################################################################

@doc Markdown.doc"""
     divides(a::OrdLocElem{T}, b::OrdLocElem{T}, checked::Bool = true) where {T <: nf_elem}
> Returns tuple (`true`,`c`) if $b$ divides $a$ where `c`*$b$ = $a$.
> If 'checked = false' the corresponding element of the numberfield is returned and it is not
> checked whether it is an element of the given localization.
"""
function divides(a::OrdLocElem{T}, b::OrdLocElem{T}, checked::Bool = true) where {T <: nf_elem}
   check_parent(a,b)

   if iszero(b)
     if iszero(a)
       return true, parent(a)()
     else
       return false, parent(a)()
     end
   end

   elem = divexact(data(a), data(b))
   if !checked
      return true, parent(a)(elem, checked)
   elseif checked && in(elem,parent(a))
      return true, parent(a)(elem)
   else
      return false, parent(a)()
   end
end

@doc Markdown.doc"""
     divexact(a::OrdLocElem{T}, b::OrdLocElem{T}, checked::Bool = true)  where {T <: nf_elem}
> Returns element 'c' of given localization s.th. `c`*$b$ = $a$ if such element exists.
> If 'checked = false' the corresponding element of the numberfield is returned and it is not
> checked whether it is an element of the given localization.
"""
function divexact(a::OrdLocElem{T}, b::OrdLocElem{T}, checked::Bool = true)  where {T <: nf_elem}
   d = divides(a, b, checked)
   d[1] ? d[2] : error("$a not divisible by $b in the given localization")
end

@doc Markdown.doc"""
     div(a::OrdLocElem{T}, b::OrdLocElem{T}, checked::Bool = true)  where {T <: nf_elem}
> Returns element `c` if $b$ divides $a$ where `c`* $b$ = $a$.
> If $b$ does not divide $a$, `0`is returned.
> If 'checked = false' the corresponding element of the numberfield is returned and it is not
> checked whether it is an element of the given localization.
"""
function div(a::OrdLocElem{T}, b::OrdLocElem{T}, checked::Bool = true)  where {T <: nf_elem}
   d = divides(a, b, checked)
   return d[2]
end

###############################################################################
#
#   GCD
#
###############################################################################

@doc Markdown.doc"""
    gcd(a::OrdLocElem{T}, b::OrdLocElem{T}) where {T <: nf_elem}
> Returns gcd of $a$ and $b$ in canonical representation.
"""
function gcd(a::OrdLocElem{T}, b::OrdLocElem{T}) where {T <: nf_elem}
   check_parent(a,b)
   iszero(a) && return canonical_unit(b) * b
   iszero(b) && return canonical_unit(a) * a
   u = parent(a)(uniformizer(prime(a)))
   n = min(valuation(a), valuation(b))
   elem = u^n
   return canonical_unit(elem) * (elem)
end


###############################################################################
#
#   GCDX
#
###############################################################################

@doc Markdown.doc"""
    gcdx(a::OrdLocElem{T}, b::OrdLocElem{T}) where {T <: nf_elem}
> Returns tuple `(g,u,v)` s.th. `g` = gcd($a$,$b$) and `g` = `u` * $a$ + `v` * $b$.
"""
function gcdx(a::OrdLocElem{T}, b::OrdLocElem{T}) where {T <: nf_elem}
   check_parent(a,b)
   par = parent(a)
   g = gcd(a,b)
   a == par() ? (g, par(), canonical_unit(b)) :
   b == par() ? (g, canonical_unit(a), par()) :
   valuation(a) > valuation(b) ? (g, par(), canonical_unit(b)) : (g, canonical_unit(a), par())
end

###############################################################################
#
#   PID
#
###############################################################################

function principal_gen(L::OrdLoc{T}, I::NfAbsOrdIdl{AnticNumberField,T}) where {T <: nf_elem}
   valuation(L(I.gen_one)) >= valuation(L(I.gen_two)) ? L(I.gen_two) : L(I.gen_one)
end


###############################################################################
#
#   Powering
#
###############################################################################

function ^(a::OrdLocElem{T}, b::Int) where {T <: nf_elem}
   return parent(a)(data(a)^b, false)
end

###############################################################################
#
#   Random Functions
#
###############################################################################

#mainly for testing
function rand(L::OrdLoc{T}, scale = (-100:100)) where {T <: nf_elem}#rand
   Qx,x = FlintQQ["x"]
   K = nf(L)
   d = degree(K)
   while true
      temp = K(rand(Qx, 0:d-1, scale))
      try
         temp = L(temp)
         return temp
      catch
      end
   end
end

###############################################################################
#
#   Promotion rules
#
###############################################################################

promote_rule(::Type{OrdLocElem{T}}, ::Type{OrdLocElem{T}}) where {T <: nf_elem} = OrdLocElem{T}


###############################################################################
#
#   Parent object call overloading
#
###############################################################################

(L::OrdLoc{T})() where {T <: nf_elem} = L(zero(nf(L)))

(L::OrdLoc{T})(a::Integer)  where {T <: nf_elem} = L(nf(L)(a))

function (L::OrdLoc{T})(data::T, checked::Bool = true) where {T <: nf_elem}
   return OrdLocElem{T}(data,L,checked)
end

function (L::OrdLoc{T})(data::NfAbsOrdElem{AnticNumberField,T}, checked::Bool = true) where {T <: nf_elem}
   return OrdLocElem{T}(nf(parent(data))(data),L,checked)
end

function (L::OrdLoc{T})(data::Rational{<: Integer}, checked::Bool = true) where {T <: nf_elem}
   return OrdLocElem{T}(nf(L)(numerator(data)) // nf(L)(denominator(data)),L,checked)
end

function (L::OrdLoc{T})(data::fmpz, checked::Bool = true) where {T <: nf_elem}
   return OrdLocElem{T}(nf(L)(data),L,checked)
end

function (L::OrdLoc{T})(a::OrdLocElem{T}) where {T <: nf_elem}
   L != parent(a) && error("No element of $L")
   return a
end

################################################################################
#
#   Valuation
#
################################################################################

@doc Markdown.doc"""
    valuation(a::OrdLocElem{T}) where {T <: nf_elem}
> Returns the valuation of $a$ at the prime localized at.
"""
function valuation(a::OrdLocElem{T}) where {T <: nf_elem}
   return valuation(data(a), prime(parent(a)))
end

@doc Markdown.doc"""
    valuation(a::OrdLocElem{T}, prime::NfAbsOrdIdl{AnticNumberField,T}) where {T <: nf_elem}
> Returns the valuation `n` of $a$ at $P$.
"""
valuation(a::OrdLocElem{T}, prime::NfAbsOrdIdl{AnticNumberField,T}) where {T <: nf_elem} = valuation(data(a), prime)

###############################################################################
#
#   Canonicalisation
#
###############################################################################

@doc Markdown.doc"""
    canonical_unit(a::OrdLocElem{T}) where {T <: nf_elem}
> Returns unit `b`::OrdLocElem{T} s.th. ($a$ * `b`) only consists of powers of the prime localized at.
"""
function canonical_unit(a::OrdLocElem{T}) where {T <: nf_elem}
   if a == parent(a)()
      return parent(a)(1)
   end
   u = parent(a)(uniformizer(prime(a)))
   n = valuation(a)
   return divexact(u^n,a)
end

###############################################################################
#
#   Constructors
#
###############################################################################

@doc Markdown.doc"""
    OrdLoc(OK::NfAbsOrd{AnticNumberField,T}, prime::NfAbsOrdIdl{AnticNumberField,T}; cached=true) where {T <: nf_elem}
> Returns the localization of the order $OK$ at the ideal $prime$. Not checked that ideal $prime$ is prime.
> If `cached == true` (the default) then the resulting
> localization parent object is cached and returned for any subsequent calls
> to the constructor with the same order $OK$ and ideal $prime$.
"""
function OrdLoc(OK::NfAbsOrd{AnticNumberField,T}, prime::NfAbsOrdIdl{AnticNumberField,T}, checked= true, cached=true) where {T <: nf_elem}
   return OrdLoc{T}(OK, prime, checked, cached)
end
