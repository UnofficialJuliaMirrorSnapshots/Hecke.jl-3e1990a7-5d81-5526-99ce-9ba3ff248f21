export left_order, right_order, normred, locally_free_basis, islocally_free

@doc Markdown.doc"""
    order(I::AlgAssRelOrdIdl) -> AlgAssRelOrd

> Returns the order containing $I$.
"""
@inline order(I::AlgAssRelOrdIdl) = I.order

iszero(I::AlgAssRelOrdIdl) = (I.iszero == 1)

###############################################################################
#
#  String I/O
#
###############################################################################

function show(io::IO, a::AlgAssRelOrdIdl)
  print(io, "Ideal of ")
  show(IOContext(io, :compact => true), order(a))
  print(io, " with basis pseudo-matrix\n")
  show(IOContext(io, :compact => true), basis_pmat(a, copy = false))
end

################################################################################
#
#  Deepcopy
#
################################################################################

function Base.deepcopy_internal(a::AlgAssRelOrdIdl, dict::IdDict)
  b = typeof(a)(order(a))
  for i in fieldnames(typeof(a))
    if isdefined(a, i)
      if i != :order
        setfield!(b, i, Base.deepcopy_internal(getfield(a, i), dict))
      end
    end
  end
  return b
end

################################################################################
#
#  "Assure" functions for fields
#
################################################################################

function assure_has_basis_pmat(a::AlgAssRelOrdIdl)
  if isdefined(a, :basis_pmat)
    return nothing
  end
  if !isdefined(a, :pseudo_basis)
    error("No pseudo_basis and no basis_pmat defined.")
  end
  pb = pseudo_basis(a, copy = false)
  A = algebra(order(a))
  M = zero_matrix(base_ring(A), dim(A), dim(A))
  C = Vector{frac_ideal_type(order_type(base_ring(A)))}()
  for i = 1:dim(A)
    elem_to_mat_row!(M, i, pb[i][1])
    push!(C, deepcopy(pb[i][2]))
  end
  M = M*basis_mat_inv(order(a), copy = false)
  a.basis_pmat = pseudo_hnf(PseudoMatrix(M, C), :lowerleft, true)
  return nothing
end

function assure_has_pseudo_basis(a::AlgAssRelOrdIdl)
  if isdefined(a, :pseudo_basis)
    return nothing
  end
  if !isdefined(a, :basis_pmat)
    error("No pseudo_basis and no basis_pmat defined.")
  end
  P = basis_pmat(a, copy = false)
  B = pseudo_basis(order(a), copy = false)
  A = algebra(order(a))
  K = base_ring(A)
  pb = Vector{Tuple{elem_type(A), frac_ideal_type(order_type(K))}}()
  for i = 1:dim(A)
    t = A()
    for j = 1:dim(A)
      t += P.matrix[i, j]*B[j][1]
    end
    push!(pb, (t, deepcopy(P.coeffs[i])))
  end
  a.pseudo_basis = pb
  return nothing
end

function assure_has_basis_mat(a::AlgAssRelOrdIdl)
  if isdefined(a, :basis_mat)
    return nothing
  end
  a.basis_mat = basis_pmat(a).matrix
  return nothing
end

function assure_has_basis_mat_inv(a::AlgAssRelOrdIdl)
  if isdefined(a, :basis_mat_inv)
    return nothing
  end
  a.basis_mat_inv = inv(basis_mat(a, copy = false))
  return nothing
end

################################################################################
#
#  Pseudo basis / basis pseudo-matrix
#
################################################################################

@doc Markdown.doc"""
    pseudo_basis(a::AlgAssRelOrdIdl; copy::Bool = true)

> Returns the pseudo basis of $a$, i. e. a vector $v$ of pairs $(e_i, a_i)$ such
> that $a = \bigoplus_i a_i e_i$, where $e_i$ is an element of the algebra
> containing $a$ and $a_i$ is a fractional ideal of `base_ring(order(a))`.
"""
function pseudo_basis(a::AlgAssRelOrdIdl; copy::Bool = true)
  assure_has_pseudo_basis(a)
  if copy
    return deepcopy(a.pseudo_basis)
  else
    return a.pseudo_basis
  end
end

@doc Markdown.doc"""
    basis_pmat(a::AlgAssRelOrdIdl; copy::Bool = true) -> PMat

> Returns the basis pseudo-matrix of $a$ with respect to the basis of the order.
"""
function basis_pmat(a::AlgAssRelOrdIdl; copy::Bool = true)
  assure_has_basis_pmat(a)
  if copy
    return deepcopy(a.basis_pmat)
  else
    return a.basis_pmat
  end
end

################################################################################
#
#  (Inverse) basis matrix
#
################################################################################

@doc Markdown.doc"""
    basis_mat(a::AlgAssRelOrdIdl; copy::Bool = true) -> MatElem

> Returns the basis matrix of $a$, that is the basis pseudo-matrix of $a$ without
> the coefficient ideals.
"""
function basis_mat(a::AlgAssRelOrdIdl; copy::Bool = true)
  assure_has_basis_mat(a)
  if copy
    return deepcopy(a.basis_mat)
  else
    return a.basis_mat
  end
end

@doc Markdown.doc"""
    basis_mat_inv(a::AlgAssRelOrdIdl; copy::Bool = true) -> MatElem

> Returns the inverse of the basis matrix of $a$.
"""
function basis_mat_inv(a::AlgAssRelOrdIdl; copy::Bool = true)
  assure_has_basis_mat_inv(a)
  if copy
    return deepcopy(a.basis_mat_inv)
  else
    return a.basis_mat_inv
  end
end

################################################################################
#
#  Arithmetic
#
################################################################################

@doc Markdown.doc"""
    +(a::AlgAssRelOrdIdl, b::AlgAssRelOrdIdl) -> AlgAssRelOrdIdl

> Returns $a + b$.
"""
function +(a::AlgAssRelOrdIdl{S, T}, b::AlgAssRelOrdIdl{S, T}) where {S, T}
  if iszero(a)
    return deepcopy(b)
  elseif iszero(b)
    return deepcopy(a)
  end

  d = degree(order(a))
  M = vcat(basis_pmat(a), basis_pmat(b))
  M = sub(pseudo_hnf(M, :lowerleft), (d + 1):2*d, 1:d)
  return ideal(order(a), M, :nothing, false, true)
end

@doc Markdown.doc"""
    *(a::AlgAssRelOrdIdl, b::AlgAssRelOrdIdl) -> AlgAssRelOrdIdl

> Returns $a \cdot b$.
"""
function *(a::AlgAssRelOrdIdl{S, T}, b::AlgAssRelOrdIdl{S, T}) where {S, T}
  if iszero(a)
    return deepcopy(a)
  elseif iszero(b)
    return deepcopy(b)
  end

  d = degree(order(a))
  pba = pseudo_basis(a, copy = false)
  pbb = pseudo_basis(b, copy = false)
  d2 = d^2
  A = algebra(order(a))

  M = zero_matrix(base_ring(A), d2, d)
  C = Array{frac_ideal_type(order_type(base_ring(A))), 1}(undef, d2)
  t = one(A)
  for i = 1:d
    i1d = (i - 1)*d
    for j = 1:d
      t = mul!(t, pba[i][1], pbb[j][1])
      elem_to_mat_row!(M, i1d + j, t)
      C[i1d + j] = simplify(pba[i][2]*pbb[j][2])
    end
  end

  H = pseudo_hnf(PseudoMatrix(M, C), :lowerleft)
  H = sub(H, (d2 - d + 1):d2, 1:d)
  H.matrix = H.matrix*basis_mat_inv(order(a), copy = false)
  H = pseudo_hnf(H, :lowerleft)
  return ideal(order(a), H, :nothing, false, true)
end

@doc Markdown.doc"""
    ^(a::AlgAssRelOrdIdl, e::Int) -> AlgAssRelOrdIdl
    ^(a::AlgAssRelOrdIdl, e::fmpz) -> AlgAssRelOrdIdl

> Returns $a^e$.
"""
^(A::AlgAssRelOrdIdl, e::Int) = Base.power_by_squaring(A, e)
^(A::AlgAssRelOrdIdl, e::fmpz) = Base.power_by_squaring(A, BigInt(e))

@doc Markdown.doc"""
    intersect(a::AlgAssRelOrdIdl, b::AlgAssRelOrdIdl) -> AlgAssRelOrdIdl

> Returns $a \cap b$.
"""
function intersect(a::AlgAssRelOrdIdl{S, T}, b::AlgAssRelOrdIdl{S, T}) where {S, T}
  d = degree(order(a))
  Ma = basis_pmat(a)
  Mb = basis_pmat(b)
  M1 = hcat(Ma, deepcopy(Ma))
  z = zero_matrix(base_ring(Ma.matrix), d, d)
  M2 = hcat(PseudoMatrix(z, Mb.coeffs), Mb)
  M = vcat(M1, M2)
  H = sub(pseudo_hnf(M, :lowerleft), 1:d, 1:d)
  return ideal(order(a), H, :nothing, false, true)
end

################################################################################
#
#  Construction
#
################################################################################

function defines_ideal(O::AlgAssRelOrd{S, T}, M::PMat{S, T}) where {S, T}
  K = base_ring(algebra(O))
  coeffs = basis_pmat(O, copy = false).coeffs
  I = PseudoMatrix(identity_matrix(K, degree(O)), deepcopy(coeffs))
  return _spans_subset_of_pseudohnf(M, I, :lowerleft)
end

@doc Markdown.doc"""
    ideal(O::AlgAssRelOrd, M::PMat, side::Symbol = :nothing, check::Bool = true,
          M_in_hnf::Bool = false)
      -> AlgAssRelOrdIdl

> Returns the ideal of $O$ with basis pseudo-matrix $M$.
> If the ideal is known to be a right/left/twosided ideal of $O$, `side` may be
> set to `:right`/`:left`/`:twosided` respectively.
> If `check == false` it is not checked whether $M$ defines an ideal of $O$.
> If `M_in_hnf == true` it is assumed that $M$ is already in lower left pseudo HNF.
"""
function ideal(O::AlgAssRelOrd{S, T}, M::PMat{S, T}, side::Symbol = :nothing, check::Bool = true, M_in_hnf::Bool = false) where {S, T}
  if check
    !defines_ideal(O, M) && error("The pseudo-matrix does not define an ideal.")
  end
  !M_in_hnf ? M = pseudo_hnf(M, :lowerleft, true) : nothing
  a = AlgAssRelOrdIdl{S, T}(O, M)
  _set_sidedness(a, side)
  return a
end

@doc Markdown.doc"""
    ideal(O::AlgAssRelOrd, M::Generic.Mat, side::Symbol = :nothing,
          check::Bool = true)
      -> AlgAssRelOrdIdl

> Returns the ideal of $O$ with basis matrix $M$.
> If the ideal is known to be a right/left/twosided ideal of $O$, `side` may be
> set to `:right`/`:left`/`:twosided` respectively.
> If `check == false` it is not checked whether $M$ defines an ideal of $O$.
"""
function ideal(O::AlgAssRelOrd{S, T}, M::Generic.Mat{S}, side::Symbol = :nothing, check::Bool = true) where {S, T}
  coeffs = deepcopy(basis_pmat(O, copy = false).coeffs)
  return ideal(O, PseudoMatrix(M, coeffs), side, check)
end

@doc Markdown.doc"""
    ideal(O::AlgAssRelOrd, x::AlgAssRelOrdElem) -> AlgAssRelOrdIdl

> Returns the twosided principal ideal of $O$ generated by $x$.
"""
function ideal(O::AlgAssRelOrd{S, T}, x::AlgAssRelOrdElem{S, T}) where {S, T}
  @assert parent(x) == O

  if iscommutative(O)
    a = ideal(O, x, :left)
    a.isright = 1
    return a
  end

  A = algebra(O)
  t1 = A()
  t2 = A()
  M = zero_matrix(base_ring(A), degree(O)^2, degree(O))
  pb = pseudo_basis(O, copy = false)
  C = Vector{T}(undef, degree(O)^2)
  for i = 1:degree(O)
    i1d = (i - 1)*degree(O)
    C[i1d + i] = pb[i][2]^2
    for j = (i + 1):degree(O)
      C[i1d + j] = simplify(pb[i][2]*pb[j][2])
      C[(j - 1)*degree(O) + i] = deepcopy(C[i1d + j])
    end
  end

  for i = 1:degree(O)
    t1 = mul!(t1, pb[i][1], elem_in_algebra(x, copy = false))
    ii = (i - 1)*degree(O)
    for j = 1:degree(O)
      t2 = mul!(t2, t1, pb[j][1])
      elem_to_mat_row!(M, ii + j, t2)
    end
  end
  M = sub(pseudo_hnf(PseudoMatrix(M, C), :lowerleft), nrows(M) - degree(O) + 1:nrows(M), 1:ncols(M))
  M.matrix = M.matrix*basis_mat_inv(O, copy = false)
  M = pseudo_hnf(M, :lowerleft)

  return ideal(O, M, :twosided, false, true)
end

@doc Markdown.doc"""
    ideal(O::AlgAssRelOrd, x::AlgAssRelOrdElem, action::Symbol) -> AlgAssRelOrdIdl

> Returns the ideal $x \cdot O$, if `action == :left`, and $O \cdot x$, if
> `action == :right`.
"""
function ideal(O::AlgAssRelOrd{S, T}, x::AlgAssRelOrdElem{S, T}, action::Symbol) where {S, T}
  @assert parent(x) == O
  M = representation_matrix(x, action)
  if action == :left
    a = ideal(O, M, :right, false)
  elseif action == :right
    a = ideal(O, M, :left, false)
  end
  if iszero(x)
    a.iszero = 1
  end
  return a
end

@doc Markdown.doc"""
    *(O::AlgAssRelOrd, x::AlgAssRelOrdElem) -> AlgAssRelOrdIdl
    *(O::AlgAssRelOrd, x::Int) -> AlgAssRelOrdIdl
    *(O::AlgAssRelOrd, x::fmpz) -> AlgAssRelOrdIdl
    *(x::AlgAssRelOrdElem, O::AlgAssRelOrd) -> AlgAssRelOrdIdl
    *(x::Int, O::AlgAssRelOrd) -> AlgAssRelOrdIdl
    *(x::fmpz, O::AlgAssRelOrd) -> AlgAssRelOrdIdl

> Returns the ideal $O \cdot x$ or $x \cdot O$ respectively.
"""
*(O::AlgAssRelOrd{S, T}, x::AlgAssRelOrdElem{S, T}) where {S, T} = ideal(O, x, :right)
*(x::AlgAssRelOrdElem{S, T}, O::AlgAssRelOrd{S, T}) where {S, T} = ideal(O, x, :left)
*(O::AlgAssRelOrd{S, T}, x::Union{ Int, fmpz }) where {S, T} = ideal(O, O(x), :right)
*(x::Union{ Int, fmpz }, O::AlgAssRelOrd{S, T}) where {S, T} = ideal(O, O(x), :left)

@doc Markdown.doc"""
    ideal(O::AlgAssRelOrd, a::NfOrdFracIdl, check::Bool = true) -> AlgAssRelOrdIdl
    ideal(O::AlgAssRelOrd, a::NfRelOrdFracIdl, check::Bool = true) -> AlgAssRelOrdIdl

> Returns the ideal $a \cdot O$ where $a$ is a fractional ideal of `base_ring(O)`.
> If `check == false` it is not checked whether this defines an ideal of $O$.
"""
function ideal(O::AlgAssRelOrd{S, T}, a::T, check::Bool = true) where {S, T}
  d = degree(O)
  pb = pseudo_basis(O, copy = false)
  M = identity_matrix(base_ring(algebra(O)), d)
  PM = PseudoMatrix(M, [ a*pb[i][2] for i = 1:d ])
  if check
    !defines_ideal(O, PM) && error("The coefficient ideal does not define an ideal.")
  end
  PM = pseudo_hnf(PM, :lowerleft)
  return ideal(O, PM, :twosided, false, true)
end

@doc Markdown.doc"""
    ideal(O::AlgAssRelOrd, a::NfAbsOrdIdl) -> AlgAssRelOrdIdl
    ideal(O::AlgAssRelOrd, a::NfRelOrdIdl) -> AlgAssRelOrdIdl

> Returns the ideal $a \cdot O$ where $a$ is an ideal of `base_ring(O)`.
"""
function ideal(O::AlgAssRelOrd{nf_elem, NfOrdFracIdl}, a::NfAbsOrdIdl)
  aa = frac_ideal(order(a), a, fmpz(1))
  return ideal(O, aa, false)
end

function ideal(O::AlgAssRelOrd, a::NfRelOrdIdl)
  @assert order(a) == order(pseudo_basis(O, copy = false)[1][2])

  aa = frac_ideal(order(a), basis_pmat(a), true)
  return ideal(O, aa, false)
end

@doc Markdown.doc"""
    *(O::AlgAssRelOrd, a::NfAbsOrdIdl) -> AlgAssRelOrdIdl
    *(O::AlgAssRelOrd, a::NfRelOrdIdl) -> AlgAssRelOrdIdl
    *(O::AlgAssRelOrd, a::NfOrdFracIdl) -> AlgAssRelOrdIdl
    *(O::AlgAssRelOrd, a::NfRelOrdFracIdl) -> AlgAssRelOrdIdl
    *(a::NfAbsOrdIdl, O::AlgAssRelOrd) -> AlgAssRelOrdIdl
    *(a::NfRelOrdIdl, O::AlgAssRelOrd) -> AlgAssRelOrdIdl
    *(a::NfOrdFracIdl, O::AlgAssRelOrd) -> AlgAssRelOrdIdl
    *(a::NfRelOrdFracIdl, O::AlgAssRelOrd) -> AlgAssRelOrdIdl

> Returns the ideal $a \cdot O$ where $a$ is a (fractional) ideal of `base_ring(O)`.
"""
*(O::AlgAssRelOrd{S, T}, a::T) where {S, T} = ideal(O, a)

*(a::T, O::AlgAssRelOrd{S, T}) where {S, T} = ideal(O, a)

*(O::AlgAssRelOrd, a::Union{NfAbsOrdIdl, NfRelOrdIdl}) = ideal(O, a)

*(a::Union{NfAbsOrdIdl, NfRelOrdIdl}, O::AlgAssRelOrd) = ideal(O, a)

@doc Markdown.doc"""
    ideal_from_lattice_gens(O::AlgAssRelOrd, gens::Vector{ <: AbsAlgAssElem },
                            check::Bool = true)
      -> AlgAssRelOrd

> Returns the ideal of $O$ generated by the elements of `gens` as a lattice over
> `base_ring(O)`.
"""
function ideal_from_lattice_gens(O::AlgAssRelOrd, gens::Vector{ <: AbsAlgAssElem }, check::Bool = true)

  M = zero_matrix(base_ring(algebra(O)), length(gens), degree(O))
  for i = 1:length(gens)
    elem_to_mat_row!(M, i, gens[i])
  end
  PM = pseudo_hnf(PseudoMatrix(M), :lowerleft)
  if length(gens) != degree(O)
    PM = sub(PM, (length(gens) - degree(O) + 1):length(gens), 1:degree(O))
  end

  return ideal(O, PM, :nothing, check, true)
end

################################################################################
#
#  Inclusion of elements in ideals
#
################################################################################

@doc Markdown.doc"""
    in(x::AlgAssRelOrdElem, a::AlgAssRelOrdIdl) -> Bool

> Returns `true` if the order element $x$ is in $a$ and `false` otherwise.
"""
function in(x::AlgAssRelOrdElem, a::AlgAssRelOrdIdl)
  parent(x) !== order(a) && error("Order of element and ideal must be equal")
  O = order(a)
  b_pmat = basis_pmat(a, copy = false)
  t = matrix(base_ring(algebra(O)), 1, degree(O), coordinates(x))
  t = t*basis_mat_inv(a, copy = false)
  for i = 1:degree(O)
    if !(t[1, i] in b_pmat.coeffs[i])
      return false
    end
  end
  return true
end

################################################################################
#
#  Equality
#
################################################################################

@doc Markdown.doc"""
    ==(a::AlgAssRelOrdIdl, b::AlgAssRelOrdIdl) -> Bool

> Returns `true` if $a$ and $b$ are equal and `false` otherwise.
"""
function ==(A::AlgAssRelOrdIdl, B::AlgAssRelOrdIdl)
  order(A) !== order(B) && return false
  return basis_pmat(A, copy = false) == basis_pmat(B, copy = false)
end

################################################################################
#
#  isleft/isright
#
################################################################################

# functions isright_ideal and isleft_ideal are in AlgAss/Ideal.jl

function _test_ideal_sidedness(a::AlgAssRelOrdIdl, side::Symbol)
  O = order(a)
  b = ideal(O, one(O))

  if side == :right
    c = a*b
  elseif side == :left
    c = b*a
  else
    error("side must be either :left or :right")
  end

  return _spans_subset_of_pseudohnf(basis_pmat(c, copy = false), basis_pmat(a, copy = false), :lowerleft)
end

################################################################################
#
#  Ring of multipliers, left and right order
#
################################################################################

function ring_of_multipliers(a::AlgAssRelOrdIdl{T1, T2}, action::Symbol = :left) where {T1, T2}
  O = order(a)
  K = base_ring(algebra(O))
  d = degree(O)
  pb = pseudo_basis(a, copy = false)
  S = basis_mat_inv(O, copy = false)*basis_mat_inv(a, copy = false)
  M = basis_mat(O, copy = false)*representation_matrix(pb[1][1], action)*S
  for i = 2:d
    M = hcat(M, basis_mat(O, copy = false)*representation_matrix(pb[i][1], action)*S)
  end
  invcoeffs = [ simplify(inv(pb[i][2])) for i = 1:d ]
  C = Array{T2}(undef, d^2)
  for i = 1:d
    for j = 1:d
      if i == j
        C[(i - 1)*d + j] = K(1)*order(pb[i][2])
      else
        C[(i - 1)*d + j] = simplify(pb[i][2]*invcoeffs[j])
      end
    end
  end
  PM = PseudoMatrix(transpose(M), C)
  PM = sub(pseudo_hnf(PM, :upperright, true), 1:d, 1:d)
  N = inv(transpose(PM.matrix))*basis_mat(O, copy = false)
  PN = PseudoMatrix(N, [ simplify(inv(I)) for I in PM.coeffs ])
  return typeof(O)(algebra(O), PN)
end

@doc Markdown.doc"""
    left_order(a::AlgAssRelOrdIdl) -> AlgAssRelOrd

> Returns the order $\{ x \in A \mid xa \subseteq a\}$, where $A$ is the algebra
> containing $a$.
"""
left_order(a::AlgAssRelOrdIdl) = ring_of_multipliers(a, :right)

@doc Markdown.doc"""
    right_order(a::AlgAssRelOrdIdl) -> AlgAssRelOrd

> Returns the order $\{ x \in A \mid ax \subseteq a\}$, where $A$ is the algebra
> containing $a$.
"""
right_order(a::AlgAssRelOrdIdl) = ring_of_multipliers(a, :left)

################################################################################
#
#  Reduction of element modulo ideal
#
################################################################################

function mod!(a::AlgAssRelOrdElem, I::AlgAssRelOrdIdl)
  O = order(I)
  b = coordinates(a, copy = false)
  PM = basis_pmat(I, copy = false) # PM is assumed to be in lower left pseudo hnf
  t = parent(b[1])()
  t1 = parent(b[1])()
  for i = degree(O):-1:1
    t = add!(t, mod(b[i], PM.coeffs[i]), -b[i])
    for j = 1:i
      t1 = mul!(t1, t, PM.matrix[i, j])
      b[j] = add!(b[j], b[j], t1)
    end
  end

  t = algebra(O)()
  B = pseudo_basis(O, copy = false)
  zero!(a.elem_in_algebra)
  for i = 1:degree(O)
    t = mul!(t, B[i][1], algebra(O)(b[i]))
    a.elem_in_algebra = add!(a.elem_in_algebra, a.elem_in_algebra, t)
  end

  return a
end

@doc Markdown.doc"""
    mod(a::AlgAssRelOrdElem, I::AlgAssRelOrdIdl) -> AlgAssRelOrdElem

> Returns $b$ in `order(I)` such that $a \equiv b \mod I$ and the coefficients
> of $b$ are reduced modulo $I$.
"""
function mod(a::AlgAssRelOrdElem, I::AlgAssRelOrdIdl)
  return mod!(deepcopy(a), I)
end

function mod!(a::AlgAssRelOrdElem, Q::RelOrdQuoRing)
  return mod!(a, ideal(Q))
end

function mod(a::AlgAssRelOrdElem, Q::RelOrdQuoRing)
  return mod(a, ideal(Q))
end

################################################################################
#
#  Norm
#
################################################################################

# Assumes, that det(basis_mat(a)) == 1
function assure_has_norm(a::AlgAssRelOrdIdl)
  if isdefined(a, :norm)
    return nothing
  end
  if iszero(a)
    O = base_ring(order(a))
    a.norm = O()*O
    return nothing
  end
  c = basis_pmat(a, copy = false).coeffs
  d = inv_coeff_ideals(order(a), copy = false)
  n = c[1]*d[1]
  for i = 2:degree(order(a))
    n *= c[i]*d[i]
  end
  simplify(n)
  @assert denominator(n) == 1
  a.norm = numerator(n)
  return nothing
end

@doc Markdown.doc"""
    norm(a::AlgAssRelOrdIdl; copy::Bool = true)

> Returns the norm of $a$ as an ideal of `base_ring(order(a))`.
"""
function norm(a::AlgAssRelOrdIdl; copy::Bool = true)
  assure_has_norm(a)
  if copy
    return deepcopy(a.norm)
  else
    return a.norm
  end
end

function assure_has_normred(a::AlgAssRelOrdIdl)
  if isdefined(a, :normred)
    return nothing
  end
  if iszero(a)
    a.normred = norm(a)
    return nothing
  end

  A = algebra(order(a))
  m = isqrt(dim(A))
  @assert m^2 == dim(A)
  N = norm(a, copy = false)
  b, I = ispower(N, m)
  @assert b "Cannot compute reduced norm. Maybe the algebra is not simple and central?"
  a.normred = I
  return nothing
end

@doc Markdown.doc"""
    normred(a::AlgAssRelOrdIdl; copy::Bool = true)

> Returns the reduced norm of $a$ as an ideal of `base_ring(order(a))`.
> It is assumed that the algebra containing $a$ is simple and central.
"""
function normred(a::AlgAssRelOrdIdl; copy::Bool = true)
  @assert dimension_of_center(algebra(order(a))) == 1
  @assert algebra(order(a)).issimple == 1
  assure_has_normred(a)
  if copy
    return deepcopy(a.normred)
  else
    return a.normred
  end
end

################################################################################
#
#  Locally free basis
#
################################################################################

@doc Markdown.doc"""
    locally_free_basis(a::AlgAssRelOrdIdl, p::Union{ NfAbsOrdIdl, NfRelOrdIdl })
      -> AlgAssRelOrdElem

> Returns an element $x$ of the order $O$ of $a$ such that $a_p = O_p \cdot b$
> where $p$ is a prime ideal of `base_ring(O)`.
> See also `islocally_free`.
"""
function locally_free_basis(I::AlgAssRelOrdIdl, p::Union{ NfAbsOrdIdl, NfRelOrdIdl })
  b, x = islocally_free(I, p)
  if !b
    error("The ideal is not locally free at the prime")
  end
  return x
end

# See Bley, Wilson "Computations in relative algebraic K-groups", section 4.2
@doc Markdown.doc"""
    islocally_free(a::AlgAssRelOrdIdl, p::Union{ NfAbsOrdIdl, NfRelOrdIdl })
      -> Bool, AlgAssRelOrdElem

> Returns a tuple `(true, x)` with an element $x$ of the order $O$ of $a$ such
> that $a_p = O_p x$ if $a$ is locally free at $p$, and `(false, 0)` otherwise.
> $p$ is a prime ideal of `base_ring(O)`.
> See also `locally_free_basis`.
"""
function islocally_free(I::AlgAssRelOrdIdl, p::Union{ NfAbsOrdIdl, NfRelOrdIdl })
  O = order(I)
  pO = p*O
  OpO, toOpO = AlgAss(O, p*O, p)
  J = radical(OpO)
  OJ, toOJ = quo(OpO, J)
  decOJ = decompose(OJ)

  pI = pO*I
  IpI, toIpI = AlgAss(I, pI, p)
  basisIpI = [ toIpI\IpI[i] for i = 1:dim(IpI) ]
  gensJ = Vector{elem_type(IpI)}()
  for b in basis(J, copy = false)
    bb = toOpO\b
    for c in basisIpI
      push!(gensJ, toIpI(bb*c))
    end
  end
  JinIpI = ideal_from_gens(IpI, gensJ)
  IJ, toIJ = quo(IpI, JinIpI)

  a = O()
  for i = 1:length(decOJ)
    A, AtoOJ = decOJ[i]
    B, AtoB, BtoA = _as_algebra_over_center(A)
    C, BtoC = _as_matrix_algebra(B)
    e = toOpO\(toOJ\(AtoOJ(BtoA(BtoC\C[1]))))
    basiseIJ = Vector{elem_type(IJ)}()
    for b in basisIpI
      bb = toIJ(toIpI(e*b))
      if !iszero(bb)
        push!(basiseIJ, bb)
      end
    end

    # Construct an Fq-basis for e*IJ where Fq \cong centre(A)
    Z, ZtoA = center(A)
    basisZ = [ toOpO\(toOJ\(AtoOJ(ZtoA(Z[i])))) for i = 1:dim(Z) ]

    basiseIJoverZ = Vector{elem_type(O)}()
    M = zero_matrix(base_ring(IJ), dim(Z), dim(IJ))
    MM = zero_matrix(base_ring(IJ), 0, dim(IJ))
    r = 0
    for i = 1:length(basiseIJ)
      b = toIpI\(toIJ\basiseIJ[i])

      for j = 1:dim(Z)
        bb = toIJ(toIpI(basisZ[j]*b))
        elem_to_mat_row!(M, j, bb)
      end

      N = vcat(MM, M)
      s = rank(N)
      if s > r
        push!(basiseIJoverZ, b)
        MM = N
        r = s
      end
      if r == length(basiseIJ)
        break
      end
    end

    if length(basiseIJoverZ) != degree(C)
      # I is not locally free
      return false, O()
    end

    for i = 1:length(basiseIJoverZ)
      a += mod(toOpO\(toOJ\(AtoOJ(BtoA(BtoC\C[i]))))*basiseIJoverZ[i], pI)
    end
  end

  return true, mod(a, pI)
end

################################################################################
#
#  p-Radical
#
################################################################################

# See Friedrichs: "Berechnung von Maximalordnungen über Dedekindringen", Algorithmus 5.1
@doc Markdown.doc"""
    pradical(O::AlgAssRelOrd, p::Union{ NfAbsOrdIdl, NfRelOrdIdl }) -> AlgAssRelOrdIdl

> Returns the ideal $\sqrt{p \cdot O}$ where $p$ is a prime ideal of `base_ring(O)`.
"""
function pradical(O::AlgAssRelOrd, p::Union{ NfAbsOrdIdl, NfRelOrdIdl })
  K = base_ring(algebra(O))
  OK = maximal_order(K)
  pO = p*O
  OpO, OtoOpO = AlgAss(O, pO, p)
  J = radical(OpO)

  if isempty(basis(J, copy = false))
    return pO
  end

  N = basis_pmat(pO, copy = false)
  t = PseudoMatrix(zero_matrix(K, 1, degree(O)))
  for b in basis(J, copy = false)
    bb = OtoOpO\b
    for i = 1:degree(O)
      t.matrix[1, i] = coordinates(bb, copy = false)[i]
    end
    N = vcat(N, deepcopy(t))
  end
  N = sub(pseudo_hnf(N, :lowerleft, true), nrows(N) - degree(O) + 1:nrows(N), 1:degree(O))
  return ideal(O, N, :twosided, false, true)
end

################################################################################
#
#  Primes lying over a prime
#
################################################################################

# See Friedrichs: "Berechnung von Maximalordnungen über Dedekindringen", Algorithmus 5.23
@doc Markdown.doc"""
    prime_ideals_over(O::AlgAssRelOrd, p::Union{ NfAbsOrdIdl, NfRelOrdIdl })
      -> Vector{AlgAssRelOrdIdl}

> Returns all prime ideal of $O$ lying over $p$ where $p$ is a prime ideal
> of `base_ring(O)`.
"""
function prime_ideals_over(O::AlgAssRelOrd, p::Union{ NfAbsOrdIdl, NfRelOrdIdl })
  return _prime_ideals_over(O, pradical(O, p), p)
end

# prad is expected to be pradical(O, p). If strict_containment == true and prad
# is already prime, we return an empty array.
function _prime_ideals_over(O::AlgAssRelOrd, prad::AlgAssRelOrdIdl, p::Union{ NfAbsOrdIdl, NfRelOrdIdl }; strict_containment::Bool = false)
  K = base_ring(algebra(O))
  OK = order(p)

  A, OtoA = AlgAss(O, prad, p)
  decA = decompose(A)

  if length(decA) == 1
    if strict_containment
      return ideal_type(O)[]
    else
      return [ prad ]
    end
  end

  lifted_components = Vector{typeof(basis_pmat(prad, copy = false))}()
  for k = 1:length(decA)
    N = zero_matrix(K, dim(decA[k][1]), degree(O))
    for i = 1:dim(decA[k][1])
      b = OtoA\(decA[k][2](decA[k][1][i]))
      for j = 1:degree(O)
        N[i, j] = coordinates(b, copy = false)[j]
      end
    end
    push!(lifted_components, PseudoMatrix(N))
  end

  primes = Vector{ideal_type(O)}()
  for i = 1:length(decA)
    N = basis_pmat(prad, copy = false)
    for j = 1:length(decA)
      if i == j
        continue
      end

      N = vcat(N, lifted_components[j])
    end
    N = sub(pseudo_hnf(N, :lowerleft, true), nrows(N) - degree(O) + 1:nrows(N), 1:degree(O))
    push!(primes, ideal(O, N, :twosided, false, true))
  end

  return primes
end

################################################################################
#
#  Random elements
#
################################################################################

@doc Markdown.doc"""
    rand(a::AlgAssRelOrdIdl, B::Int) -> AlgAssRelOrdElem

> Returns a random element of $a$ whose coefficient size is controlled by $B$.
"""
function rand(a::AlgAssRelOrdIdl, B::Int)
  pb = pseudo_basis(a, copy = false)
  z = algebra(order(a))()
  for i = 1:degree(order(a))
    t = rand(pb[i][2], B)
    z += t*pb[i][1]
  end
  return order(a)(z)
end
