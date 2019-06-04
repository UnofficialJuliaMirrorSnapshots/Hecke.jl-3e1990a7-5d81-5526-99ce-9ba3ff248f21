
module QAdic

using Hecke

mutable struct qAdicRootCtx
  f::fmpz_poly
  p::Int
  n::Int
  Q::Array{FlintQadicField, 1}
  H::Hecke.HenselCtx
  R::Array{qadic, 1}
  function qAdicRootCtx(f::fmpz_poly, p::Int)
    r = new()
    r.f = f
    r.p = p
    r.H = H = Hecke.factor_mod_pk_init(f, p)
    lf = Hecke.factor_mod_pk(H, 1)
    #TODO:XXX: Careful: QadicField ONLY works, currently, in Conway range
    Q = [QadicField(p, x, 1) for x = Set(degree(y) for y = keys(lf))]
    @assert all(isone, values(lf))
    r.Q = Q
    return r
  end
end

function Hecke.precision(H::Hecke.HenselCtx)
  return Int(H.N)
end

function Hecke.prime(H::Hecke.HenselCtx)
  return Int(H.p)
end

function Base.setprecision(q::qadic, N::Int)
  r = parent(q)()
  r.N = N
  ccall((:padic_poly_set, :libflint), Nothing, (Ref{qadic}, Ref{qadic}, Ref{FlintQadicField}), r, q, parent(q))
  return r
end

export setprecision!

function setprecision!(q::qadic, N::Int)
  @assert N >= q.N
  q.N = N
  return q
end

function setprecision!(f::Generic.Poly{qadic}, N::Int)
  for i=1:length(f)
    f.coeffs[i].N = N
  end
  return f
end

#XXX: valuation(Q(0)) == 0 !!!!!
function newton_lift(f::fmpz_poly, r::qadic)
  Q = parent(r)
  n = Q.prec_max
  i = n
  chain = [n]
  while i>2
    i = div(i+1, 2)
    push!(chain, i)
  end
  fs = derivative(f)
  qf = change_base_ring(f, Q)
  qfs = change_base_ring(fs, Q)
  o = Q(r)
  o.N = 1
  s = qf(r)
  o = inv(setprecision!(qfs, 1)(o))
  @assert r.N == 1
  for p = reverse(chain)
    r.N = p
    o.N = p
    Q.prec_max = r.N
    setprecision!(qf, r.N)
    setprecision!(qfs, r.N)
    r = r - qf(r)*o
    if r.N >= n
      Q.prec_max = n
      return r
    end
    o = o*(2-qfs(r)*o)
  end
end

function Hecke.setcoeff!(x::fq_nmod, n::Int, u::UInt)
  ccall((:nmod_poly_set_coeff_ui, :libflint), Nothing, 
                (Ref{fq_nmod}, Int, UInt), x, n, u)
end

function Hecke.coeff(x::qadic, i::Int)
  R = FlintPadicField(prime(parent(x)), parent(x).prec_max)
  c = R()
  ccall((:padic_poly_get_coeff_padic, :libflint), Nothing, 
           (Ref{padic}, Ref{qadic}, Int, Ref{FlintQadicField}), c, x, i, parent(x))
  return c         
end

function Hecke.setcoeff!(x::qadic, i::Int, y::padic)
  ccall((:padic_poly_set_coeff_padic, :libflint), Nothing, 
           (Ref{qadic}, Int, Ref{padic}, Ref{FlintQadicField}), x, i, y, parent(x))
end
function Hecke.setcoeff!(x::qadic, i::Int, y::UInt)
  R = FlintPadicField(prime(parent(x)), parent(x).prec_max)
  Y = R(fmpz(y))
  ccall((:padic_poly_set_coeff_padic, :libflint), Nothing, 
           (Ref{qadic}, Int, Ref{padic}, Ref{FlintQadicField}), x, i, Y, parent(x))
end

function Hecke.ResidueField(Q::FlintQadicField)
  k = GF(Int(prime(Q)), degree(Q))[1]
  pro = function(x::qadic)
    v = valuation(x)
    v < 0 && error("elt non integral")
    v > 0 && return k(0)
    z = k()
    for i=0:degree(Q)
      setcoeff!(z, i, UInt(lift(coeff(x, i))%prime(Q)))
    end
    return z
  end
  lif = function(x::fq_nmod)
    z = Q()
    for i=0:degree(Q)
      setcoeff!(z, i, coeff(x, i))
    end
    return z
  end
  return k, MapFromFunc(pro, lif, Q, k)
end

function Hecke.roots(f::fmpz_poly, Q::FlintQadicField; max_roots::Int = degree(f))
  k, mk = ResidueField(Q)
  rt = roots(f, k)
  RT = qadic[]
  for r = rt
    push!(RT, newton_lift(f, preimage(mk, r)))
    if length(RT) >= max_roots
      return RT
    end
  end
  return RT
end

function Hecke.roots(C::qAdicRootCtx, n::Int = 10)
  if isdefined(C, :R) && all(x -> x.N >= n, C.R)
    return [setprecision(x, n) for x = C.R]
  end
  lf = Hecke.factor_mod_pk(C.H, n)
  rt = qadic[]
  for Q = C.Q
    Q.prec_max = n
    for x = keys(lf)
      if degree(x) == degree(Q)
        append!(rt, roots(x, Q, max_roots = 1))
      end
    end
  end
  C.R = rt
  return rt
end

#TODO: refine roots....

mutable struct qAdicConj
  K::AnticNumberField
  C::qAdicRootCtx
  function qAdicConj(K::AnticNumberField, p::Int)
    Zx = PolynomialRing(FlintZZ, cached = false)[1]
    C = qAdicRootCtx(Zx(K.pol), p)
    r = new()
    r.C = C
    r.K = K
    return r
  end
end

function Hecke.conjugates(a::nf_elem, C::qAdicConj, n::Int = 10)
  return _conjugates(a, C, n, x -> x)
end
#TODO: implement a proper Frobneius - with caching of the frobenius_a element
function _conjugates(a::nf_elem, C::qAdicConj, n::Int, op::Function; flat::Bool = true, all::Bool = false)
  R = roots(C.C, n)
  @assert parent(a) == C.K
  Zx = PolynomialRing(FlintZZ, cached = false)[1]
  d = denominator(a)
  f = Zx(d*a)
  res = qadic[]
  for x = R
    a = op(inv(parent(x)(d))*f(x))::qadic
    push!(res, a)
    if all
      i = 2
      while i < degree(parent(a))
        a = frobenius(a)
        push!(res, a)
        i += 1
      end
    end
  end
  if !flat
    return res
  end
  re = padic[]
  for x = res
    for i=1:degree(parent(x))
      push!(re, coeff(x, i-1))
    end
  end
  return matrix(parent(re[1]), 1, length(re), re)
end

function _log(a::qadic)
  q = prime(parent(a))^degree(parent(a))
  return log(a^(q-1))//(q-1)
  return log(a*inv(teichmuller(a)))
end

log_cache = Dict{nf_elem, Any}()
function Hecke.conjugates_log(a::nf_elem, C::qAdicConj, n::Int = 10)
  global log_cache
  if haskey(log_cache, a)
    b = log_cache[a]
    if b[1,1].N == n
      return b
    end
  end
  return log_cache[a] = _conjugates(a, C, n, _log)
end

function Hecke.conjugates_log(a::FacElem{nf_elem, AnticNumberField}, C::qAdicConj, n::Int = 10)
  local res::Generic.MatSpaceElem{padic}
  first = true
  for (k, v) = a.fac
    try 
      y = conjugates_log(k, C, n)
      if first
        res = v*y
        first = false
      else
        res += v*y
      end
    catch e
      if isa(e, DivideError) || isa(e, DomainError)
        lp = prime_decomposition(maximal_order(parent(k)), C.C.p)
        @assert all(x -> Hecke.has_2_elem_normal(x[1]), lp)
        val = map(x -> valuation(k, x[1]), lp)
        pe = prod(lp[i][1].gen_two^val[i] for i = 1:length(lp) if val[i] != 0)
        aa = k//pe
        y = conjugates_log(aa, C, n)
        if first
          res = v*y
          first = false
        else
          res += v*y
        end
      else
        rethrow(e)
      end
    end
  end
  return res
end


function mult_syzygies_units(A::Array{FacElem{nf_elem, AnticNumberField}, 1})
  p = next_prime(100)
  K = base_ring(parent(A[1]))
  m = maximum(degree, keys(factor(K.pol, GF(p)).fac))
  while m > 4
    p = next_prime(p)
    m = maximum(degree, keys(factor(K.pol, GF(p)).fac))
  end
         #experimentally, the runtime is dominated by log
  u = FacElem{nf_elem, AnticNumberField}[]
  prec = 640

  r1, r2 = signature(K)
  r = r1+r2 -1
  n = degree(K)
  C = qAdicConj(K, p)
  la = conjugates_log(A[1], C, prec)
  lu = zero_matrix(base_ring(la), 0, n)
  uu = []
  for a = A
    while true
      @time la = conjugates_log(a, C, prec)
      if iszero(la)
        @time @assert verify_gamma([a], [fmpz(1)], fmpz(p)^prec)
        println("torsion found")
        break
      end
      lv = vcat(lu, la)
      #check_precision and change
      if false && any(x->precision(x) < prec, lv)
        println("loss of precision - not sure what to do")
        for i=1:rows(lv)
          for j = cols(lv) #seems to not do anything
            lv[i, j] = setprecision(lv[i, j], min_p)
            @assert precision(lv[i,j]) == min_p
          end
        end
      end
      @time k = Hecke.left_kernel_basis(lv)
      @assert length(k) < 2
      if length(k) == 0
        println("new ")
        push!(u, a)
        lu = vcat(lu, la)
        @assert length(u) <= r
      else # length == 1 extend the module
        s = fmpq[]
        for x = k[1]
          @time y = lift_reco(FlintQQ, x, reco = true)
          if y == nothing
            prec *= 2
            @show "increase prec to ", prec
            lu = vcat([conjugates_log(x, C, prec) for x = u])
            break
          end
          push!(s, y)
        end
        if length(s) < length(k[1])
          continue
        end
        d = reduce(lcm, map(denominator, s))
        gamma = fmpz[FlintZZ(x*d)::fmpz for x = s] 
        @assert reduce(gcd, gamma) == 1 # should be a primitive relation
        @time if !verify_gamma(push!(copy(u), a), gamma, fmpz(p)^prec)
          prec *= 2
          @show "increase prec to ", prec
          lu = vcat([conjugates_log(x, C, prec) for x = u])
          continue
        end
        @assert length(gamma) == length(u)+1
        gamma = vcat(gamma[1:length(u)], [0 for i=length(u)+1:r+length(uu)], [gamma[end]])
        push!(uu, (a, gamma))
      end
      break
    end
  end
  #=
    let u_1, .., u_n be units and
       <u_i | i> has rank s and 
        r_i in Z^n be such that
          prod u_i^r_i = 1  (OK, sum of the logs is zero)
          rank <r_i | i> = s as well
    so the r_i form a Q-basis for the relations.
    Essentially, the gamma of above are the r_i
    Let [H|0] = [r_i|i]*T be the hnf with trafo, so T in Gl(n, Z)
    Then
      <u_i|i> = <[u_i|i] T>
      [r_i|i] * [u_i|i]^t = 0 (by construction)
      [r_i|i] T inv(T) [u[i] | i] = 0
      [H | 0]   [v_i | i] = 0
      so, since H is triangular(!!) v_1, ... v_n-s = 0
      and <u_i |i> = <v_n-s+1, ..., v_n>
    
    for the case of n=s+1 this is mostly the "normal" construction.
    Note: as a side, the relations do not have to be primitive.
      If they are, (and n=s+1), then H = 1
  =#

  for i=1:length(uu)-1
    append!(uu[i][2], zeros(FlintZZ, length(uu[end][2])-length(uu[i][2])))
  end
  if length(uu) == 0
    @show uu
    U = matrix(FlintZZ, length(uu), length(uu[end][2]), reduce(vcat, [x[2] for x = uu]))
  else
    U = matrix(FlintZZ, length(uu), length(uu[end][2]), reduce(vcat, [x[2] for x = uu]))
  end
  _, U = hnf_with_transform(U')
  if false
    U = inv(U)
    V = sub(U, 1:rows(U), 1:cols(U)-length(u))
    U = sub(U, 1:rows(U), cols(U)-length(u)+1:cols(U))
    #U can be reduced modulo V...
    Z = zero_matrix(FlintZZ, cols(V), cols(U))
    I = identity_matrix(FlintZZ, cols(U)) * p^(2*prec)
    k = base_ring(A[1])
    A = [ Z V'; I U']
    l = lll(A)
    U = sub(l, cols(V)+1:rows(l), cols(U)+1:cols(l))
    U = lll(U)
  else
    U = lll(U')
  end
  return Hecke._transform(vcat(u, FacElem{nf_elem,AnticNumberField}[FacElem(k(1)) for i=length(u)+1:r], [x[1] for x = uu]), U')
end

function verify_gamma(a::Array{FacElem{nf_elem, AnticNumberField}, 1}, g::Array{fmpz, 1}, v::fmpz)
  #knowing that sum g[i] log(a[i]) == 0 mod v, prove that prod a[i]^g[i] is
  #torsion
  #= I claim N(1-a) > v^n for n the field degree:
   Let K be one of the p-adic fields involved, set b = a^g
   then log(K(b)) = 0 (v = p^l) by assumption
   so val(log(K(b))) >= l, but
   val(X) = 1/deg(K) val(norm(X)) for p-adics
   This is true for all completions involved, and sum degrees is n
 =#

  t = prod([a[i]^g[i] for i=1:length(a)])
  # t is either 1 or 1-t is large, norm(1-t) is div. by p^ln
  #in this case T2(1-t) is large, by the arguments above: T2>= (np^l)^2=:B
  # and, see the bottom, \|Log()\|_2^2 >= 1/4 arcosh((B-2)/2)^2
  B = ArbField(nbits(v)*2)(v)^2
  B = 1/2 *acosh((B-2)/2)^2
  p = Hecke.upper_bound(log(B)/log(parent(B)(2)), fmpz)
  @show "using", p, nbits(v)*2
  b = conjugates_arb_log(t, max(-Int(div(p, 2)), 2))
  global res = (B, b, t)
#  @show B , sum(x*x for x = b), istorsion_unit(t)[1]
  @assert (B > sum(x*x for x = b)) == istorsion_unit(t)[1]
  return B > sum(x*x for x = b)
end


function Hecke.prime(R::PadicField, i::Int)
  p = fmpz()
  ccall((:padic_ctx_pow_ui, :libflint), Cvoid, (Ref{fmpz}, Int, Ref{PadicField}), p, i, R)
  return p
end

function getUnit(a::padic)
  u = fmpz()
  ccall((:fmpz_set, :libflint), Cvoid, (Ref{fmpz}, Ref{Int}), u, a.u)
  return u, a.v, a.N
end

function lift_reco(::FlintRationalField, a::padic; reco::Bool = false)
  if reco
    u, v, N = getUnit(a)
    R = parent(a)
    fl, c, d = rational_reconstruction(u, prime(R, N-v))
    !fl && return nothing
    if false && 2*max(nbits(c), nbits(d)) > nbits(prime(R, N-v)) -20 #arbitrary 
      @show "bad"
      return nothing
    end
    @assert fl
    x = FlintQQ(c, d)
    if v < 0
      return x//prime(R, -v)
    else
      return x*prime(R, v)
    end
  else
    return lift(FlintQQ, a)
  end
end

function Hecke.FlintZZ(x::Rational{Int})
  @assert denominator(x) == 1
  return fmpz(numerator(x))
end

import Base.*

function *(A::fmpz_mat, B::MatElem{padic})
  return matrix(base_ring(B), A) * B
end

uniformizer(Q::FlintQadicField) = Q(prime(Q))
Base.precision(Q::FlintQadicField) = Q.prec_max

function expand(a::qadic)
  @assert valuation(a-1)>0
  i = 1
  Q = parent(a)
  pi = uniformizer(Q)
  x = qadic[]
  while true
    b = divexact((a-1), pi)
    b = setprecision(b, i)
    push!(x, b)
    b = setprecision(b, precision(Q)-i)
    @show a = a*inv(1+pi*b)
    pi = pi^2
    i = 2*i
    if i > precision(Q)
      return x
    end
  end
end

################################################################################
#
# (q/p)adic integers
# 
# complete enough to support hnf
################################################################################

struct QadicRing{T} <: Generic.Ring
  Q::T
end

function Base.show(io::IO, Q::QadicRing)
  println("Integers of ", Q.Q)
end

function Hecke.ring_of_integers(Q::FlintQadicField)
  return QadicRing{FlintQadicField}(Q)
end

function Hecke.ring_of_integers(Q::FlintPadicField)
  return QadicRing{FlintPadicField}(Q)
end

struct QadicRingElem{S} <: RingElem
  x::S
  P::QadicRing
  function QadicRingElem(a::qadic, P::QadicRing)
    r = new{qadic}(a, P)
  end
  function QadicRingElem(a::padic, P::QadicRing)
    r = new{padic}(a, P)
  end
end

function Base.show(io::IO, a::QadicRingElem)
  print(io, a.x)
end
  
import Base.*, Base.==, Base.+, Base.inv, Hecke.divexact, Hecke.canonical_unit,
       Base.-

*(a::QadicRingElem, b::QadicRingElem) = QadicRingElem(a.x*b.x, a.P)
+(a::QadicRingElem, b::QadicRingElem) = QadicRingElem(a.x+b.x, a.P)
-(a::QadicRingElem, b::QadicRingElem) = QadicRingElem(a.x-b.x, a.P)
-(a::QadicRingElem) = QadicRingElem(-a.x, a.P)

function inv(a::QadicRingElem) 
  valuation(a.x) == 0 || error("non unit")
  return QadicRingElem(inv(a.x), a.P)
end

==(a::QadicRingElem, b::QadicRingElem) = a.x == b.x 

function divexact(a::QadicRingElem, b::QadicRingElem)
  @assert !iszero(b.x)
  valuation(a.x) >= valuation(b.x) && return QadicRingElem(a.x//b.x, a.P)
end

function divrem(a::QadicRingElem, b::QadicRingElem)
  if valuation(a.x) < valuation(b.x)
    return a.P(0), a 
  end
  q = divexact(a, b)
  return q, a-q*b
end

function Base.div(a::QadicRingElem, b::QadicRingElem)
  if valuation(a.x) < valuation(b.x)
    return a.P(0)
  end
  q = divexact(a, b)
  return q
end


Hecke.parent(a::QadicRingElem) = a.P
Hecke.elem_type(::Type{QadicRing{FlintPadicField}}) = QadicRingElem{padic}
Hecke.elem_type(::Type{QadicRing{FlintQadicField}}) = QadicRingElem{qadic}
Hecke.parent_type(::Type{QadicRingElem{padic}}) = QadicRing{FlintPadicField}
Hecke.parent_type(::Type{QadicRingElem{qadic}}) = QadicRing{FlintQadicField}
Hecke.zero(Q::QadicRing) = QadicRingElem(Q.Q(0), Q)
Hecke.one(Q::QadicRing) = QadicRingElem(Q.Q(1), Q)
(Q::QadicRing)(a::QadicRingElem) = QadicRingElem(a.x, a.P)
(Q::QadicRing)(a::Int) = QadicRingElem(Q.Q(a), Q)
(Q::QadicRing)() = QadicRingElem(Q.Q(), Q)
Hecke.valuation(a::QadicRingElem) = valuation(a.x)
Hecke.isunit(a::QadicRingElem) = valuation(a) == 0
function Base.deepcopy_internal(a::QadicRingElem, dict::IdDict)
  return QadicRingElem(a.x, a.P)
end
function Hecke.canonical_unit(a::QadicRingElem)
  iszero(a.x) && return a.P(1)
  v = valuation(a.x)
  return QadicRingElem(inv(a.x//prime(a.P.Q)^v), a.P)
end

function Hecke.gcdx(a::QadicRingElem, b::QadicRingElem)
  if valuation(a.x) < valuation(b.x)
    c = canonical_unit(a)
    return a*c, c, a.P(0)
  else
    c = canonical_unit(b)
    return b*c, b.P(0), c
  end
end

function Hecke.mul_red!(a::QadicRingElem, b::QadicRingElem, c::QadicRingElem, f::Bool = false)
  return b*c
end

function Hecke.mul!(a::QadicRingElem, b::QadicRingElem, c::QadicRingElem)
  return b*c
end

function Hecke.add!(a::QadicRingElem, b::QadicRingElem, c::QadicRingElem)
  return b+c
end

function Hecke.addeq!(a::QadicRingElem, b::QadicRingElem)
  return a+b
end

Base.iszero(a::QadicRingElem) = iszero(a.x)
Base.isone(a::QadicRingElem) = isone(a.x)
 
end
