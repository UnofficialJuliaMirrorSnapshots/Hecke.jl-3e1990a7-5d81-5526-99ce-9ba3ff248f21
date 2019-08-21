
module QAdic

using Hecke, Profile

Hecke.add_assert_scope(:PolyFactor)
Hecke.add_verbose_scope(:PolyFactor)

Hecke.add_verbose_scope(:qAdic)
Hecke.add_assert_scope(:qAdic)

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
  prec = 10

  r1, r2 = signature(K)
  r = r1+r2 -1
  n = degree(K)
  C = qAdicConj(K, p)
  la = conjugates_log(A[1], C, prec)
  lu = zero_matrix(base_ring(la), 0, n)
  uu = []
  for a = A
    while true
      @vtime :qAdic 1 la = conjugates_log(a, C, prec)
      if iszero(la)
        @vtime :qAdic 1 @hassert :qAdic 1 verify_gamma([a], [fmpz(1)], fmpz(p)^prec)
        @vprint :qAdic 1 println("torsion found")
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
      @vtime :qAdic 1 k = Hecke.left_kernel_basis(lv)
      @assert length(k) < 2
      if length(k) == 0
        println("new ")
        push!(u, a)
        lu = vcat(lu, la)
        @assert length(u) <= r
      else # length == 1 extend the module
        s = fmpq[]
        for x = k[1]
          @vtime :qAdic 1 y = lift_reco(FlintQQ, x, reco = true)
          if y == nothing
            prec *= 2
            @vprint :qAdic 1  "increase prec to ", prec
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
          @vprint :qAdic 1 "increase prec to ", prec
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
  @vprint :qAdic 1  "using", p, nbits(v)*2
  b = conjugates_arb_log(t, max(-Int(div(p, 2)), 2))
#  @show B , sum(x*x for x = b), istorsion_unit(t)[1]
  @hassert :qAdic 1 (B > sum(x*x for x = b)) == istorsion_unit(t)[1]
  return B > sum(x*x for x = b)
end

function lift_reco(::FlintRationalField, a::padic; reco::Bool = false)
  if reco
    u, v, N = getUnit(a)
    R = parent(a)
    fl, c, d = rational_reconstruction(u, prime(R, N-v))
    !fl && return nothing
    
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

Hecke.nrows(A::Array{T, 2}) where {T} = size(A)[1]
Hecke.ncols(A::Array{T, 2}) where {T} = size(A)[2]

#########################
#
#########################

abstract type Hensel end
mutable struct HenselCtxQadic <: Hensel
  f::PolyElem{qadic}
  lf::Array{PolyElem{qadic}, 1}
  la::Array{PolyElem{qadic}, 1}
  p::qadic
  n::Int
  #TODO: lift over subfields first iff poly is defined over subfield
  #TODO: use flint if qadic = padic!!
  function HenselCtxQadic(f::PolyElem{qadic}, lfp::Array{fq_nmod_poly, 1})
    @assert sum(map(degree, lfp)) == degree(f)
    Q = base_ring(f)
    Qx = parent(f)
    K, mK = ResidueField(Q)
    i = 1
    la = Array{PolyElem{qadic}, 1}()
    n = length(lfp)
    while i < length(lfp)
      f1 = lfp[i]
      f2 = lfp[i+1]
      g, a, b = gcdx(f1, f2)
      @assert isone(g)
      push!(la, setprecision(change_base_ring(a, x->preimage(mK, x), Qx), 1))
      push!(la, setprecision(change_base_ring(b, x->preimage(mK, x), Qx), 1))
      push!(lfp, f1*f2)
      i += 2
    end
    return new(f, map(x->setprecision(change_base_ring(x, y->preimage(mK, y), Qx), 1), lfp), la, uniformizer(Q), n)
  end

  function HenselCtxQadic(f::PolyElem{qadic})
    Q = base_ring(f)
    K, mK = ResidueField(Q)
    fp = change_base_ring(f, mK)
    lfp = collect(keys(factor(fp).fac))
    return HenselCtxQadic(f, lfp)
  end
end

function Base.show(io::IO, C::HenselCtxQadic)
  println(io, "Lifting tree for $(C.f), with $(C.n) factors, currently up precision $(valuation(C.p))")
end

function Hecke.lift(C::HenselCtxQadic, mx::Int = minimum(precision, coefficients(C.f)))
  p = C.p
  N = valuation(p)
#  @show map(precision, coefficients(C.f)), N, precision(parent(p))
  #have: N need mx
  ch = [mx] 
  while ch[end] > N
    push!(ch, div(ch[end]+1, 2))
  end
  @vprint :PolyFactor 1 "using lifting chain ", ch
  for k=length(ch)-1:-1:1
    N2 = ch[k]
    i = length(C.lf)
    j = i-1
    p = setprecision(p, N2)
    while j > 0
      if i==length(C.lf)
        f = setprecision(C.f, N2)
      else
        f = setprecision(C.lf[i], N2)
      end
      #formulae and names from the Flint doc
      h = C.lf[j]
      g = C.lf[j-1]
      b = C.la[j]
      a = C.la[j-1]
      setprecision!(h, N2)
      setprecision!(g, N2)
      setprecision!(a, N2)
      setprecision!(b, N2)

      fgh = (f-g*h)*inv(p)
      G = rem(fgh*b, g)*p+g
      H = rem(fgh*a, h)*p+h
      t = (1-a*G-b*H)*inv(p)
      B = rem(t*b, g)*p+b
      A = rem(t*a, h)*p+a
      if i < length(C.lf)
        C.lf[i] = G*H
      end
      C.lf[j-1] = G
      C.lf[j] = H
      C.la[j-1] = A
      C.la[j] = B
      i -= 1
      j -= 2
    end
  end
end

function Hecke.factor(C::HenselCtxQadic)
  return C.lf[1:C.n]
end

function Hecke.precision(C::HenselCtxQadic)
  return valuation(C.p)
end

# interface to use Bill's Z/p^k lifting code. same algo as above, but 
# tighter implementation
mutable struct HenselCtxPadic <: Hensel
  X::Hecke.HenselCtx
  f::PolyElem{padic}
  function HenselCtxPadic(f::PolyElem{padic})
    r = new()
    r.f = f
    Zx = PolynomialRing(FlintZZ, cached = false)[1]
    ff = Zx()
    for i=0:degree(f)
      setcoeff!(ff, i, lift(coeff(f, i)))
    end
    r.X = Hecke.HenselCtx(ff, prime(base_ring(f)))
    Hecke.start_lift(r.X, 1)
    return r
  end
end

function Hecke.lift(C::HenselCtxPadic, mx::Int) 
  for i=0:degree(C.f)
    setcoeff!(C.X.f, i, lift(coeff(C.f, i)))
  end
  Hecke.continue_lift(C.X, mx)
end

function Hecke.factor(C::HenselCtxPadic)
  res =  typeof(C.f)[]
  Zx = PolynomialRing(FlintZZ, cached = false)[1]
  h = Zx()
  Qp = base_ring(C.f)
  for i = 1:C.X.LF._num #from factor_to_dict
    #cannot use factor_to_dict as the order will be random (hashing!)
    g = parent(C.f)()
    ccall((:fmpz_poly_set, :libflint), Nothing, (Ref{fmpz_poly}, Ref{Hecke.fmpz_poly_raw}), h, C.X.LF.poly+(i-1)*sizeof(Hecke.fmpz_poly_raw))
    for j=0:degree(h)
      setcoeff!(g, j, Qp(coeff(h, j)))
    end
    push!(res, g)
  end
  return res
end

function Hecke.precision(C::HenselCtxPadic)
  return Int(C.X.N)
end

function Hecke.precision(H::Hecke.HenselCtx)
  return Int(H.N)
end

function Hecke.prime(H::Hecke.HenselCtx)
  return Int(H.p)
end

function Base.round(::Type{fmpz}, a::fmpz, b::fmpz) 
  s = sign(a)
  as = abs(a)
  r = s*div(2*as+b, 2*b)
#  global rnd = (a, b)
#  @assert r == round(fmpz, a//b)
  return r
end

function div_preinv(a::fmpz, b::fmpz, bi::Hecke.fmpz_preinvn_struct)
  q = fmpz()
  r = fmpz()
  Hecke.fdiv_qr_with_preinvn!(q, r, a, b, bi)
  return q
end

function Base.round(::Type{fmpz}, a::fmpz, b::fmpz, bi::Hecke.fmpz_preinvn_struct) 
  s = sign(a)
  as = abs(a)
  r = s*div_preinv(2*as+b, 2*b, bi)
#  global rnd = (a, b)
#  @assert r == round(fmpz, a//b)
  return r
end

function Base.round(::Type{fmpz}, a::fmpz, b::fmpz)
  s = sign(a)
  as = abs(a)
  r = s*div(2*as+b, 2*b)
#  global rnd = (a, b)
#  @assert r == round(fmpz, a//b)
  return r
end
  

function reco(a::fmpz, M, pM::Tuple{fmpz_mat, fmpz, Hecke.fmpz_preinvn_struct}, O)
  m = matrix(FlintZZ, 1, degree(O), map(x -> round(fmpz, a*x, pM[2], pM[3]), pM[1][1, :]))*M
  return a - O(collect(m))
end

function reco(a::fmpz, M, pM::Tuple{fmpz_mat, fmpz}, O)
  m = matrix(FlintZZ, 1, degree(O), map(x -> round(fmpz, a*x, pM[2]), pM[1][1, :]))*M
  return a - O(collect(m))
end

function reco(a::NfAbsOrdElem, M, pM)
  m = matrix(FlintZZ, 1, degree(parent(a)), coordinates(a))
  m = m - matrix(FlintZZ, 1, degree(parent(a)), map(x -> round(fmpz, x, pM[2]), m*pM[1]))*M
  return parent(a)(collect(m))
end

function reco_inv(a::NfAbsOrdElem, M, pM)
  m = matrix(FlintZZ, 1, degree(parent(a)), coordinates(a))
  m = m - matrix(FlintZZ, 1, degree(parent(a)), map(x -> round(fmpz, x//pM[2]), m*pM[1]))*M
  return parent(a)(collect(m*pM[1]))
end

function reco(a::nf_elem, M, pM)
  m = matrix(FlintZZ, 1, degree(parent(a)), [FlintZZ(coeff(a, i)) for i=0:degree(parent(a))-1])
  m = m - matrix(FlintZZ, 1, degree(parent(a)), map(x -> round(fmpz, x//pM[2]), m*pM[1]))*M
  return parent(a)(parent(parent(a).pol)(collect(m)))
end

function myfactor(f::fmpz_poly, k::AnticNumberField)
  return myfactor(change_base_ring(f, k))
end

function myfactor(f::fmpq_poly, k::AnticNumberField)
  return myfactor(change_base_ring(f, k))
end

function myfactor(f::PolyElem{nf_elem})
  k = base_ring(f)
  zk = maximal_order(k)
  p = degree(f)
  np = 0
  bp = 1*zk
  br = 0
  s = Set{Int}()
  while true
    p = next_prime(p)
    if isindex_divisor(zk, p)
      continue
    end
    P = prime_decomposition(zk, p, 1)
    if length(P) == 0
      continue
    end
    F, mF = ResidueField(zk, P[1][1])
    mF = Hecke.extend(mF, k)
    lf = factor(change_base_ring(f, mF))
    if any(i -> i>1, values(lf.fac))
      continue
    end
    ns = Hecke._ds(lf)
    if length(s) == 0
      s = ns
    else
      s = Base.intersect(s, ns)
    end

    if length(s) == 1
      println("irreducible by degset")
      return [f]
    end

    if br == 0 || br > length(lf.fac)
      br = length(lf.fac)
      bp = P[1][1]
    end
    np += 1
    if np > 2 && br > 10
      break
    end
    if np > 2*degree(f)
      break
    end
  end
  println("possible degrees: ", s)
  if br < 5
    return zassenhaus(f, bp, degset = s)
  else
    return van_hoeij(f, bp)
  end
end

function zassenhaus(f::fmpz_poly, P::NfOrdIdl)
  return zassenhaus(change_base_ring(f, nf(order(P))), P, N)
end

function zassenhaus(f::fmpq_poly, P::NfOrdIdl)
  return zassenhaus(change_base_ring(f, nf(order(P))), P, N)
end

function zassenhaus(f::PolyElem{nf_elem}, P::NfOrdIdl; degset::Set{Int} = Set{Int}(collect(1:degree(f))))
  K = base_ring(parent(f))
  C, mC = completion(K, P)

  b = Hecke.landau_mignotte_bound(f)
  c1, c2 = Hecke.norm_change_const(order(P))
  N = ceil(Int, degree(K)/2/degree(P)*(log2(c1*c2) + 2*nbits(b)))
  @vprint :PolyFactor 1 "using a precision of $N\n"

  setprecision!(C, N)

  vH = vanHoeijCtx()
  if degree(P) == 1
    vH.H = HenselCtxPadic(change_base_ring(f, x->coeff(mC(x), 0)))
  else
    vH.H = HenselCtxQadic(change_base_ring(f, mC))
  end
  vH.C = C
  vH.P = P

  @vtime :PolyFactor 1 grow_prec!(vH, N)

  H = vH.H

  M = vH.Ml
  pM = vH.pMr

  lf = factor(H)
  zk = order(P)

  if degree(P) == 1
    S = Set(map(x -> change_base_ring(x, y -> lift(y), parent(f)), lf))
  else
    S = Set(map(x -> change_base_ring(x, y -> preimage(mC, y), parent(f)), lf))
  end
  #TODO: test reco result for being small, do early abort
  #TODO: test selected coefficients first without computing the product
  #TODO: once a factor is found (need to enumerate by size!!!), remove stuff...
  #    : if f is the norm of a poly over a larger field, then every
  #      combination has to respect he prime splitting in the extension
  #      the norm(poly) is the prod of the local norm(poly)s
  #TODO: add/use degree sets and search restrictions. Users might want restricted degrees
  #TODO: add a call to jump from van Hoeij to Zassenhaus once a partitioning 
  #      is there.
  used = empty(S)
  res = typeof(f)[]
  for d = 1:length(S)
    for s = Hecke.subsets(S, d)
      if length(Base.intersect(used, s)) > 0 
        println("re-using data")
        continue
      end
      #TODO: test constant term first, possibly also trace + size
      g = prod(s)
      g = change_base_ring(g, x->K(reco(zk(x), M, pM)))
      if iszero(rem(f, g))
        push!(res, g)
        used = union(used, s)
        if length(used) == length(S)
          return res
        end
      else
        println("reco failed")
      end
    end
  end
  return res
end

###############################################
Base.log2(a::fmpz) = log2(BigInt(a))

function initial_prec(f::PolyElem{nf_elem}, p::Int, r::Int = degree(f))
  b = minimum(Hecke.cld_bound(f, [0,degree(f)-2])) #deg(f)-1 will always be deg factor
  a = ceil(Int, (2.5*r*degree(base_ring(f))+log2(b) + log2(degree(f))/2)/log2(p))
  return a
end

function cld_data(H::Hensel, up_to::Int, from::Int, mC, Mi)
  lf = factor(H)
  a = preimage(mC, zero(codomain(mC)))
  k = parent(a)
  N = degree(H.f)
  @assert 0<= up_to <= N  #up_tp: modulo x^up_tp
  @assert 0<= from <= N   #from : div by x^from
#  @assert up_to <= from

  M = zero_matrix(FlintZZ, length(lf), (1+up_to + N - from) * degree(k))

  lf = [Hecke.divexact_low(Hecke.mullow(derivative(x), H.f, up_to), x, up_to) for x = lf]

  NN = zero_matrix(FlintZZ, 1, degree(k))
  d = FlintZZ()
  for i=0:up_to
    for j=1:length(lf)
      c = preimage(mC, coeff(lf[j], i)) # should be an nf_elem
      elem_to_mat_row!(NN, 1, d, c)
      mul!(NN, NN, Mi) #base_change, Mi should be the inv-lll-basis-mat wrt field
      @assert isone(d)
      for h=1:degree(k)
        M[j, i*degree(k) + h] = NN[1, h]
      end
    end
  end
  lf = factor(H)
  lf = [Hecke.divhigh(Hecke.mulhigh(derivative(x), H.f, from), x, from) for x = lf]
  for i=from:N-1
    for j=1:length(lf)
      c = preimage(mC, coeff(lf[j], i)) # should be an nf_elem
      elem_to_mat_row!(NN, 1, d, c)
      mul!(NN, NN, Mi) #base_change, Mi should be the inv-lll-basis-mat wrt field
      @assert isone(d)
      for h=1:degree(k)
        M[j, (i-from+up_to)*degree(k) + h] = NN[1, h]
      end
    end
  end
  return M
end

function van_hoeij(f::fmpz_poly, P::NfOrdIdl)
  return van_hoeij(change_base_ring(f, nf(order(P))), P)
end

function van_hoeij(f::fmpq_poly, P::NfOrdIdl)
  return van_hoeij(change_base_ring(f, nf(order(P))), P)
end

mutable struct vanHoeijCtx
  H::Hensel
  pr::Int
  Ml::fmpz_mat
  pMr::Tuple{fmpz_mat, fmpz, Hecke.fmpz_preinvn_struct}
  pM::Tuple{fmpz_mat, fmpz}
  C::Union{FlintQadicField, FlintPadicField}
  P::NfOrdIdl
  function vanHoeijCtx()
    return new()
  end
end

function grow_prec!(vH::vanHoeijCtx, pr::Int)
  lift(vH.H, pr)

  vH.Ml = lll(basis_mat(vH.P^pr))
  pMr = pseudo_inv(vH.Ml)
  F = FakeFmpqMat(pMr)
  #M * basis_mat(zk) is the basis wrt to the field
  #(M*B)^-1 = B^-1 * M^-1, so I need basis_mat_inv(zk) * pM
  vH.pMr = (F.num, F.den, Hecke.fmpz_preinvn_struct(2*F.den))
  F = basis_mat_inv(order(vH.P)) * F
  vH.pM = (F.num, F.den)
end


function van_hoeij(f::PolyElem{nf_elem}, P::NfOrdIdl; prec_scale = 20)
  K = base_ring(parent(f))
  C, mC = completion(K, P)

  _, mK = ResidueField(order(P), P)
  mK = extend(mK, K)
  r = length(factor(change_base_ring(f, mK)))
  N = degree(f)
  @vprint :PolyFactor 1  "Having $r local factors for degree ", N

  setprecision!(C, 5)

  vH = vanHoeijCtx()
  if degree(P) == 1
    vH.H = HenselCtxPadic(change_base_ring(f, x->coeff(mC(x), 0)))
  else
    vH.H = HenselCtxQadic(change_base_ring(f, mC))
  end
  vH.C = C
  vH.P = P

  up_to = min(5, ceil(Int, N/20))
  up_to_start = up_to
  from = N-up_to  #use 5 coeffs on either end
  up_to = min(up_to, N)
  from = min(from, N)
  from = max(up_to, from)
  b = Hecke.cld_bound(f, vcat(0:up_to-1, from:N-1))

  # from Fieker/Friedrichs, still wrong here
  # needs to be larger than anticipated...
  c1, c2 = Hecke.norm_change_const(order(P))
  b = [ceil(Int, degree(K)/2/degree(P)*(log2(c1*c2) + 2*nbits(x)+ prec_scale)) for x = b]
  @vprint :PolyFactor 2 "using CLD precsion bounds ", b

  used = []
  really_used = []
  M = identity_matrix(FlintZZ, r)*2^prec_scale

  while true #the main loop
    #find some prec
    #to start with, I want at least half of the CLDs to be useful
    i= sort(b)[div(length(b)+1, 2)]
    @vprint :PolyFactor 1 "setting prec to $i, and lifting the info ...\n"
    setprecision!(codomain(mC), i)
    if degree(P) == 1
      vH.H.f = change_base_ring(f, x->coeff(mC(x), 0))
    else
      vH.H.f = change_base_ring(f, mC)
    end
    @vtime :PolyFactor 1 grow_prec!(vH, i)

   
    av_bits = sum(nbits, vH.Ml)/degree(K)^2
    @vprint :PolyFactor 1 "obtaining CLDs...\n"

    #prune: in Swinnerton-Dyer: either top or bottom are too large.
    while from < N && b[N - from + up_to] > i
      from += 1
    end
    while up_to > 0 && b[up_to] > i
      up_to -= 1
    end
    b = b[vcat(1:up_to, length(b)-(N-from-1):length(b))]
    have = vcat(0:up_to-1, from:N-2)  #N-1 is always 1

    if degree(P) == 1
      mD = MapFromFunc(x->coeff(mC(x),0), y->K(lift(y)), K, base_ring(vH.H.f))
      @vtime :PolyFactor 1 C = cld_data(vH.H, up_to, from, mD, vH.pM[1]) 
    else
      @vtime :PolyFactor 1 C = cld_data(vH.H, up_to, from, mC, vH.pM[1]) 
    end

    # In the end, p-adic precision needs to be large enough to
    # cover some CLDs. If you want the factors, it also has to 
    # cover those. The norm change constants also come in ...
    # and the degree of P...

    # starting precision:
    # - large enough to recover factors (maybe)
    # - large enough to recover some CLD (definitely)
    # - + eps to give algo a chance.
    # Then take 10% of the CLD, small enough for the current precision
    # possibly figure out which CLD's are available at all

    # we want
    # I |  C/p^n
    # 0 |   I
    # true factors, in this lattice, are small (the lower I is the rounding)
    # the left part is to keep track of operations
    # by cld_bound, we know the expected upper size of the rounded legal entries
    # so we scale it by the bound. If all would be exact, the true factors would be zero...
    # 1st make integral:
    # I | C
    # 0 | p^n
    # scale:
    # I | C/lambda
    # 0 | p^n/lambda  lambda depends on the column
    # now, to limit damages re-write the rationals with den | 2^k (rounding)
    # I | D/2^k
    #   | X/2^k
    #make integral
    # 2^k | D
    #  0  | X   where X is still diagonal
    # is all goes like planned: lll with reduction will magically work...
    # needs (I think): fix a in Z_k, P and ideal. Then write a wrt. a LLL basis of P^k
    #  a = sum a^k_i alpha^k_i, a^k_i in Q, then for k -> infty, a^k_i -> 0
    #  (ineffective: write coeffs with Cramer's rule via determinants. The
    #  numerator has n-1 LLL-basis vectors and one small vector (a), thus the
    #  determinant is s.th. ^(n-1) and the coeff then ()^(n-1)/()^n should go to zero
    # lambda should be chosen, so that the true factors become < 1 by it
    # for the gradual feeding, we can also add the individual coefficients (of the nf_elems) individually


    # - apply transformations already done (by checking the left part of the matrix)
    # - scale, round
    # - call lll_with_removel
    # until done (whatever that means)
    # if unlucky: re-do Hensel and start over again, hopefull retaining some info
    # can happen if the CLD coeffs are too large for the current Hensel level
    
    while length(have) > length(used)
      m = (b[1], 1)
      for i=1:length(have)
        if have[i] in used
          continue
        end
        if b[i] < m[1]
          m = (b[i], i)
        end
      end
      n = have[m[2]]
      push!(used, n)
      
      i = findfirst(x->x == n, have) #new data will be in block i of C
      @vprint :PolyFactor 2 "trying to use coeff $n which is $i\n"
      if b[i] > precision(codomain(mC))
        @show "not enough precisino for CLD ", i
        error()
        continue
      end
      sz = floor(Int, degree(K)*av_bits/degree(P) - b[i])

      B = sub(C, 1:r, (i-1)*degree(K)+1:i*degree(K))
#      B = sub(C, 1:r, (i-1)*degree(K)+5:(i-1)*degree(K)+7) #attempt to use parts of a coeff
#      @show i, maximum(nbits, B)
      
      T = sub(M, 1:nrows(M), 1:r)
      B = T*B   # T contains the prec_scale 
      mod_sym!(B, vH.pM[2]*fmpz(2)^prec_scale)
#      @show maximum(nbits, B), nbits(vH.pM[2]), b[i]
      if sz + prec_scale >= nbits(vH.pM[2]) || sz < 0
        println("loss of precision for this col: ", sz, " ", nbits(pM[2]))
        error()
        continue
      else
        sz = nbits(vH.pM[2]) - 2 * prec_scale
      end
      push!(really_used, n)
#      @show sz, nbits(vH.pM[2])
      ccall((:fmpz_mat_scalar_tdiv_q_2exp, :libflint), Nothing, (Ref{fmpz_mat}, Ref{fmpz_mat}, Cint), B, B, sz)
      s = max(0, sz - prec_scale)
      d = tdivpow2(vH.pM[2], s)
      M = [M B; zero_matrix(FlintZZ, ncols(B), ncols(M)) d*identity_matrix(FlintZZ, ncols(B))]
  #    @show map(nbits, Array(M))
#      @show maximum(nbits, Array(M)), size(M)
      @vtime :PolyFactor 1 l, M = lll_with_removal(M, r*fmpz(2)^(2*prec_scale) + div(r+1, 2)*N*degree(K))
#      @show l, i# , map(nbits, Array(M))
  #    @show hnf(sub(M, 1:l, 1:r))
      @hassert :PolyFactor 1 !iszero(sub(M, 1:l, 1:r))
      M = sub(M, 1:l, 1:ncols(M))
      d = Dict{fmpz_mat, Array{Int, 1}}()
      for l=1:r
        k = M[:, l]
        if haskey(d, k)
          push!(d[k], l)
        else
          d[k] = [l]
        end
      end
      @vprint :PolyFactor 1 "partitioning  of local factors: $(values(d))\n"
      if length(keys(d)) <= nrows(M)
#        @show "BINGO", length(keys(d)), "factors"
        res = typeof(f)[]
        fail = []
        if length(keys(d)) == 1
          return [f]
        end
#        display(d)
        for v = values(d)
          #trivial test:
          a = prod(map(constant_coefficient, factor(vH.H)[v]))
          if degree(P) == 1
            A = K(reco(order(P)(lift(a)), vH.Ml, vH.pMr))
          else
            A = K(reco(order(P)(preimage(mC, a)), vH.Ml, vH.pMr))
          end
          if denominator(divexact(constant_coefficient(f), A), order(P)) != 1
            push!(fail, v)
            if length(fail) > 1
              break
            end
            continue
          end
          @time g = prod(factor(vH.H)[v])
          if degree(P) == 1
            @profile G = parent(f)([K(reco(lift(coeff(g, l)), vH.Ml, vH.pMr, order(P))) for l=0:degree(g)])
          else
            @time G = parent(f)([K(reco(order(P)(preimage(mC, coeff(g, l))), vH.Ml, vH.pMr)) for l=0:degree(g)])
          end

          if !iszero(rem(f, G))
            push!(fail, v)
            if length(fail) > 1
              break
            end
            continue
          end
          push!(res, G)
        end
        if length(fail) == 1
          @vprint :PolyFactor 1 "only one reco failed, total success\n"
          return res
        end
        if length(res) < length(d)
          @vprint :PolyFactor 1 "reco failed\n... here we go again ...\n"
        else
          return res
        end
      end
    end

    up_to = up_to_start = min(2*up_to_start, N)
    up_to = min(N, up_to)
    from = N-up_to 
    from = min(from, N)
    from = max(up_to, from)

    have = vcat(0:up_to-1, from:N-2)  #N-1 is always 1
    if length(have) <= length(really_used)
      @show have, really_used, used
      error("too bad")
    end
    used = deepcopy(really_used)

    b = Hecke.cld_bound(f, vcat(0:up_to-1, from:N-1))

    # from Fieker/Friedrichs, still wrong here
    # needs to be larger than anticipated...
    b = [ceil(Int, degree(K)/2/degree(P)*(log2(c1*c2) + 2*nbits(x)+ prec_scale)) for x = b]
  end #the big while
end

function map!(f, M::fmpz_mat)
  for i=1:nrows(M)
    for j=1:ncols(M)
      M[i,j] = f(M[i,j])
    end
  end
end

#does not seem to be faster than the direct approach. (not modular)
#Magma is faster, which seems to suggest the direct resultant is
#even better (modular resultant)
# power series over finite fields are sub-par...or at least this usage
# fixed "most" of it...
function norm_mod(f::PolyElem{nf_elem}, Zx)
  p = Hecke.p_start
  K = base_ring(f)

  g = Zx(0)
  d = fmpz(1)

  while true
    p = next_prime(p)
    k = GF(p)
    me = modular_init(K, p)
    t = Hecke.modular_proj(f, me)
    tt = lift(Zx, Hecke.power_sums_to_polynomial(sum(map(x -> map(y -> k(coeff(trace(y), 0)), Hecke.polynomial_to_power_sums(x, degree(f)*degree(K))), t))))
    prev = g
    if isone(d)
      g = tt
      d = fmpz(p)
    else
      g, d = induce_crt(g, d, tt, fmpz(p), true)
    end
    if prev == g
      return g
    end
    if nbits(d) > 2000
      error("too bad")
    end
  end
end

end

set_printing_mode(FlintPadicField, :terse)
#=
  Daniel:
  let a_i be a linear recurrence sequence or better
    sum_1^infty a_i x^-i = -f/g is rational, deg f<deg g < n/2
    run rational reconstruction on h := sum_0^n a_i x^(n-i) and x^n
    finding bh = a mod x^n (h = a/b mod x^n)
    then b = g and f = div(a-bh, x^n)
    establishing the link between rat-recon and Berlekamp Massey

=#    
