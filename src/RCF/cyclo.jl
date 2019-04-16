export CyclotomicExt, cyclotomic_extension

################################################################################
#
#  Type definition
#
################################################################################
mutable struct CyclotomicExt
  k::AnticNumberField
  n::Int
  Kr::Hecke.NfRel{nf_elem}
  Ka::AnticNumberField
  mp::Tuple{NfRelToNf, NfToNfMor}
  function CyclotomicExt()
    return new()
  end
end

function Base.show(io::IO, c::CyclotomicExt)
  print(io, "Cyclotomic extension by zeta_$(c.n) of degree $(degree(c.Ka))")
end

################################################################################
#
#  Interface and creation
#
################################################################################

@doc Markdown.doc"""
    cyclotomic_extension(k::AnticNumberField, n::Int) -> CyclotomicExt
Computes $k(\zeta_n)$, in particular, a structure containing $k(\zeta_n)$
both as an absolute extension, as a relative extension (of $k$) and the maps
between them.
"""
function cyclotomic_extension(k::AnticNumberField, n::Int)
  Ac = CyclotomicExt[]
  try 
    Ac = Hecke._get_cyclotomic_ext_nf(k)::Vector{CyclotomicExt}
    for i = Ac
      if i.n == n
        return i
      end
    end
  catch e
    if !(e isa AbstractAlgebra.AccessorNotSetError)
      rethrow(e)
    end
  end
  
  kt, t = PolynomialRing(k, "t", cached = false)
  c = CyclotomicExt()
  c.k = k
  c.n = n
  
  if n == 2
    #Easy, just return the field
    Kr = number_field(t+1, cached = false, check = false)[1]
    rel2abs = NfRelToNf(Kr, k, gen(k), k(-1), Kr(gen(k)))
    small2abs = id_hom(k)
    c.Kr = Kr
    c.Ka = k
    c.mp = (rel2abs, small2abs)

    push!(Ac, c)
    Hecke._set_cyclotomic_ext_nf(k, Ac)
    return c
  end
  
  ZX, X = PolynomialRing(FlintZZ, cached = false)
  f = cyclotomic(n, X)
  fk = change_ring(f, kt)
  if n < 5
    #For n = 3, 4 the cyclotomic polynomial has degree 2,
    #so we can just ask for the roots.
    rt = _roots_hensel(fk, max_roots = 1, isnormal = true)
    if length(rt) == 1
      #The polynomial splits completely!
      Kr, gKr = number_field(t - rt[1], cached = false, check = false)
      rel2abs = NfRelToNf(Kr, k, gen(k), rt[1], Kr(gen(k)))
      small2abs = id_hom(k)
      c.Kr = Kr
      c.Ka = k
      c.mp = (rel2abs, small2abs)
    else
      Kr, Kr_gen = number_field(fk, "z_$n", cached = false, check = false)
      Ka, rel2abs, small2abs = Hecke.absolute_field(Kr, false)

      Zk = maximal_order(k)
      b_k = basis(Zk, k)
      B_k = nf_elem[small2abs(x) for x = b_k]
      g = rel2abs(Kr_gen)
      g1 = one(Ka)
      for i = 1:degree(fk)-1
        mul!(g1, g1, g)
        for j = 1:degree(k)
          push!(B_k, B_k[j]*g1)
        end
      end
      ZKa = Hecke.NfOrd(B_k)
      for (p,v) = factor(gcd(discriminant(Zk), fmpz(n))).fac
        ZKa = pmaximal_overorder(ZKa, p)
      end
      ZKa = lll(ZKa)
      ZKa.ismaximal = 1
      Hecke._set_maximal_order_of_nf(Ka, ZKa)
      c.Kr = Kr
      c.Ka = Ka
      c.mp = (rel2abs, small2abs)
    end
    push!(Ac, c)
    Hecke._set_cyclotomic_ext_nf(k, Ac)
    return c
  end
  lf = factor(fk)
  fk = first(keys(lf.fac))

  Kr, Kr_gen = number_field(fk, "z_$n", cached = false, check = false)
  if degree(fk) != 1
    Ka, rel2abs, small2abs = Hecke.absolute_field(Kr, false)
    
    # An equation order defined from a factor of a 
    # cyclotomic polynomial is always maximal by Dedekind
    # hence the product basis should be maximal at all primes except
    # for all p dividing the gcd()
    Zk = maximal_order(k)
    b_k = basis(Zk, k)
    B_k = nf_elem[small2abs(x) for x = b_k]
    g = rel2abs(Kr_gen)
    g1 = one(Ka)
    for i = 1:degree(fk)-1
      mul!(g1, g1, g)
      for j = 1:degree(k)
        push!(B_k, B_k[j]*g1)
      end
    end
    ZKa = Hecke.NfOrd(B_k)
    for (p,v) = factor(gcd(discriminant(Zk), fmpz(n))).fac
      ZKa = pmaximal_overorder(ZKa, p)
    end
    ZKa = lll(ZKa)
    ZKa.ismaximal = 1
    Hecke._set_maximal_order_of_nf(Ka, ZKa)
  else
    Ka = k
    rel2abs = NfRelToNf(Kr, Ka, gen(Ka), -coeff(fk, 0), Kr(gen(Ka)))
    small2abs = id_hom(k)
    ZKa = maximal_order(k)
  end

  c.Kr = Kr
  c.Ka = Ka
  c.mp = (rel2abs, small2abs)

  push!(Ac, c)
  Hecke._set_cyclotomic_ext_nf(k, Ac)
  return c
  
end

absolute_field(C::CyclotomicExt) = C.Ka
base_field(C::CyclotomicExt) = C.k

################################################################################
#
#  Automorphisms for cyclotomic extensions
#
################################################################################
@doc Markdown.doc"""
    automorphisms(C::CyclotomicExt; gens::Vector{NfToNfMor}) -> Vector{NfToNfMor}
Computes the automorphisms of the absolute field defined by the cyclotomic extension, i.e. of absolute_field(C).
gens must be a set of generators for the automorphism group of the base field of C
"""
function automorphisms(C::CyclotomicExt; gens::Vector{NfToNfMor} = small_generating_set(automorphisms(base_field(C))), copy::Bool = true)

  if degree(absolute_field(C)) == degree(base_field(C))
    return automorphisms(C.Ka, copy = copy)
  end
  genK = C.mp[1]\gen(C.Ka)
  gnew = Hecke.NfToNfMor[]
  #First extend the old generators
  for g in gens
    ng = Hecke.extend_to_cyclotomic(C, g)
    na = hom(C.Ka, C.Ka, C.mp[1](ng(genK)), check = false)
    push!(gnew, na)
  end 
  #Now add the automorphisms of the relative extension
  R = ResidueRing(FlintZZ, C.n, cached = false)
  U, mU = unit_group(R)
  if iscyclic(U)
    k = degree(C.Kr)
    expo = divexact(eulerphi(fmpz(C.n)), k)
    l = hom(C.Kr, C.Kr, gen(C.Kr)^Int(lift(mU(U[1])^expo)), check = false)
    l1 = hom(C.Ka, C.Ka, C.mp[1](l(C.mp[1]\gen(C.Ka))), check = false)
    #@assert iszero(Kc.Ka.pol(l1(gen(Kc.Ka)))) 
    push!(gnew, l1)
  else
    f = C.Kr.pol
    s, ms = sub(U, [x for x in U if iszero(f(gen(C.Kr)^Int(lift(mU(x)))))], false)
    S, mS = snf(s)
    for t = 1:ngens(S)
      l = hom(C.Kr, C.Kr, gen(C.Kr)^Int(lift(mU(ms(mS(S[t]))))), check = false)
      push!(gnew, hom(C.Ka, C.Ka, C.mp[1](l(genK)), check = false))
    end
  end
  auts = closure(gnew, degree(C.Ka))
  Hecke._set_automorphisms_nf(C.Ka, auts)
  if copy
    return Base.copy(auts)
  else
    return auts
  end

end
