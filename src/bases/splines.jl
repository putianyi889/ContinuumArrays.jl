
struct Spline{order,T} <: Basis{T}
    points::Vector{T}
end

const LinearSpline{T} = Spline{1,T}
const HeavisideSpline{T} = Spline{0,T}

Spline{o}(pts::AbstractVector{T}) where {o,T} = Spline{o,float(T)}(pts)

axes(B::Spline{o}) where o =
    (Inclusion(first(B.points)..last(B.points)), OneTo(length(B.points)+o-1))
==(A::Spline{o}, B::Spline{o}) where o = A.points == B.points

function getindex(B::LinearSpline{T}, x::Real, k::Int) where T
    x ∈ axes(B,1) && 1 ≤ k ≤ size(B,2)|| throw(BoundsError())

    p = B.points
    n = length(p)

    k > 1 && x ≤ p[k-1] && return zero(T)
    k < n && x ≥ p[k+1] && return zero(T)
    x == p[k] && return one(T)
    x < p[k] && return (x-p[k-1])/(p[k]-p[k-1])
    return (x-p[k+1])/(p[k]-p[k+1]) # x ≥ p[k]
end

function getindex(B::HeavisideSpline{T}, x::Real, k::Int) where T
    x ∈ axes(B,1) && 1 ≤ k ≤ size(B,2)|| throw(BoundsError())

    p = B.points
    n = length(p)

    x < p[k] && return zero(T)
    k < n && x > p[k+1] && return zero(T)
    return one(T)
end


function copyto!(dest::SymTridiagonal,
                 AB::QMul2{<:QuasiAdjoint{<:Any,<:LinearSpline},<:LinearSpline}) where T
    Ac,B = AB.args
    A = parent(Ac)
    A.points == B.points || throw(ArgumentError())
    dv,ev = dest.dv,dest.ev
    x = A.points; n = length(x)
    length(dv) == n || throw(DimensionMismatch())

    dv[1] = (x[2]-x[1])/3
    @inbounds for k = 2:n-1
        dv[k] = (x[k+1]-x[k-1])/3
    end
    dv[n] = (x[n] - x[n-1])/3

    @inbounds for k = 1:n-1
        ev[k] = (x[k+1]-x[k])/6
    end

    dest
end

## Sub-bases


## Mass matrix
function similar(AB::QMul2{<:QuasiAdjoint{<:Any,<:LinearSpline},<:LinearSpline}, ::Type{T}) where T
    n = size(AB,1)
    SymTridiagonal(Vector{T}(undef, n), Vector{T}(undef, n-1))
end
#
materialize(M::QMul2{<:QuasiAdjoint{<:Any,<:LinearSpline},<:LinearSpline}) =
    copyto!(similar(M, eltype(M)), M)

function materialize(M::QMul2{<:QuasiAdjoint{<:Any,<:HeavisideSpline},<:HeavisideSpline})
    Ac, B = M.args
    axes(Ac,2) == axes(B,1) || throw(DimensionMismatch("axes must be same"))
    A = parent(Ac)
    A.points == B.points || throw(ArgumentError("Cannot multiply incompatible splines"))
    Diagonal(diff(A.points))
end

## Derivative
function copyto!(dest::MulQuasiMatrix{<:Any,<:QMul2{<:HeavisideSpline,<:Any}},
                 M::QMul2{<:Derivative,<:LinearSpline})
    D, L = M.args
    H, A = dest.applied.args
    x = H.points

    axes(dest) == axes(M) || throw(DimensionMismatch("axes must be same"))
    x == L.points || throw(ArgumentError("Cannot multiply incompatible splines"))
    bandwidths(A) == (0,1) || throw(ArgumentError("Not implemented"))

    d = diff(x)
    A[band(0)] .= inv.((-).(d))
    A[band(1)] .= inv.(d)

    dest
end

function similar(M::QMul2{<:Derivative,<:LinearSpline}, ::Type{T}) where T
    D, B = M.args
    n = size(B,2)
    MulQuasiMatrix(HeavisideSpline{T}(B.points),
        BandedMatrix{T}(undef, (n-1,n), (0,1)))
end

materialize(M::QMul2{<:Derivative,<:LinearSpline}) =
    copyto!(similar(M, eltype(M)), M)
