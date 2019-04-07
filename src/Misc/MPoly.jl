###############################################################################
# other stuff, trivia and non-trivia
###############################################################################

function Nemo.PolynomialRing(R::Nemo.Ring, n::Int, s::String="x";
                             cached::Bool = false, ordering::Symbol = :lex)
  return Nemo.PolynomialRing(R, ["$s$i" for i=1:n], cached = cached,
                                                    ordering = ordering)
end

function add!(c::fmpq_mpoly, a::fmpq_mpoly, b::fmpq_mpoly)
  ccall((:fmpq_mpoly_add, :libflint), Nothing,
        (Ref{fmpq_mpoly}, Ref{fmpq_mpoly}, Ref{fmpq_mpoly}, Ref{FmpqMPolyRing}),
        c, a, b, c.parent)
  return c
end

#TODO: makes only sense if f is univ (uses only one var)
function (Rx::FmpzPolyRing)(f::fmpq_mpoly)
  fp = Rx()
  R = base_ring(Rx)
  d = denominator(f)
  @assert d == 1
  for t = terms(f)
    e = total_degree(t)
    @assert length(t) == 1
    c = coeff(t, 1)
    setcoeff!(fp, e, numerator(c*d))
  end
  return fp
end

function (Rx::FmpqPolyRing)(f::fmpq_mpoly)
  fp = Rx()
  R = base_ring(Rx)
  for t = terms(f)
    e = total_degree(t)
    @assert length(t) == 1
    c = coeff(t, 1)
    setcoeff!(fp, e, c)
  end
  return fp
end

function (Rx::GFPPolyRing)(f::fmpq_mpoly)
  fp = Rx()
  R = base_ring(Rx)
  d = denominator(f)
  for t = terms(f)
    e = total_degree(t)
    @assert length(t) == 1
    c = coeff(t, 1)
    setcoeff!(fp, e, R(numerator(c*d)))
  end
  return fp * inv(R(d))
end

