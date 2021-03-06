## Matrix factorizations and decompositions

abstract Factorization{T}

eltype{T}(::Type{Factorization{T}}) = T
transpose(F::Factorization) = error("transpose not implemented for $(typeof(F))")
ctranspose(F::Factorization) = error("ctranspose not implemented for $(typeof(F))")

macro assertposdef(A, info)
   :(($info)==0 ? $A : throw(PosDefException($info)))
end

macro assertnonsingular(A, info)
   :(($info)==0 ? $A : throw(SingularException($info)))
end

####################
# QR Factorization #
####################

immutable QR{T,S<:AbstractMatrix} <: Factorization{T}
    factors::S
    τ::Vector{T}
    QR(factors::AbstractMatrix{T}, τ::Vector{T}) = new(factors, τ)
end
QR{T}(factors::AbstractMatrix{T}, τ::Vector{T}) = QR{T,typeof(factors)}(factors, τ)
# Note. For QRCompactWY factorization without pivoting, the WY representation based method introduced in LAPACK 3.4
immutable QRCompactWY{S,M<:AbstractMatrix} <: Factorization{S}
    factors::M
    T::M
    QRCompactWY(factors::AbstractMatrix{S}, T::AbstractMatrix{S}) = new(factors, T)
end
QRCompactWY{S}(factors::AbstractMatrix{S}, T::AbstractMatrix{S}) = QRCompactWY{S,typeof(factors)}(factors, T)

immutable QRPivoted{T,S<:AbstractMatrix} <: Factorization{T}
    factors::S
    τ::Vector{T}
    jpvt::Vector{BlasInt}
    QRPivoted(factors::AbstractMatrix{T}, τ::Vector{T}, jpvt::Vector{BlasInt}) = new(factors, τ, jpvt)
end
QRPivoted{T}(factors::AbstractMatrix{T}, τ::Vector{T}, jpvt::Vector{BlasInt}) = QRPivoted{T,typeof(factors)}(factors, τ, jpvt)

function qrfact!{T}(A::AbstractMatrix{T}, pivot::Union(Type{Val{false}}, Type{Val{true}})=Val{false})
    pivot==Val{true} && warn("pivoting only implemented for Float32, Float64, Complex64 and Complex128")
    m, n = size(A)
    τ = zeros(T, min(m,n))
    @inbounds begin
        for k = 1:min(m-1+!(T<:Real),n)
            τk = elementaryLeft!(A, k, k)
            τ[k] = τk
            for j = k+1:n
                vAj = A[k,j]
                for i = k+1:m
                    vAj += conj(A[i,k])*A[i,j]
                end
                vAj = conj(τk)*vAj
                A[k,j] -= vAj
                for i = k+1:m
                    A[i,j] -= A[i,k]*vAj
                end
            end
        end
    end
    QR(A, τ)
end
qrfact!{T<:BlasFloat}(A::StridedMatrix{T}, pivot::Union(Type{Val{false}}, Type{Val{true}})=Val{false}) = pivot==Val{true} ? QRPivoted(LAPACK.geqp3!(A)...) : QRCompactWY(LAPACK.geqrt!(A, min(minimum(size(A)), 36))...)
qrfact{T<:BlasFloat}(A::StridedMatrix{T}, pivot::Union(Type{Val{false}}, Type{Val{true}})=Val{false}) = qrfact!(copy(A), pivot)
copy_oftype{T}(A::StridedMatrix{T}, ::Type{T}) = copy(A)
copy_oftype{T,S}(A::StridedMatrix{T}, ::Type{S}) = convert(AbstractMatrix{S}, A)
qrfact{T}(A::StridedMatrix{T}, pivot::Union(Type{Val{false}}, Type{Val{true}})=Val{false}) = qrfact!(copy_oftype(A, typeof(one(T)/norm(one(T)))), pivot)
qrfact(x::Number) = qrfact(fill(x,1,1))

qr(A::Union(Number, AbstractMatrix), pivot::Union(Type{Val{false}}, Type{Val{true}})=Val{false}; thin::Bool=true) =
    _qr(A, pivot, thin=thin)
function _qr(A::Union(Number, AbstractMatrix), ::Type{Val{false}}; thin::Bool=true)
    F = qrfact(A, Val{false})
    full(F[:Q], thin=thin), F[:R]
end
function _qr(A::Union(Number, AbstractMatrix), ::Type{Val{true}}; thin::Bool=true)
    F = qrfact(A, Val{true})
    full(F[:Q], thin=thin), F[:R], F[:p]
end

convert{T}(::Type{QR{T}},A::QR) = QR(convert(AbstractMatrix{T}, A.factors), convert(Vector{T}, A.τ))
convert{T}(::Type{Factorization{T}}, A::QR) = convert(QR{T}, A)
convert{T}(::Type{QRCompactWY{T}},A::QRCompactWY) = QRCompactWY(convert(AbstractMatrix{T}, A.factors), convert(AbstractMatrix{T}, A.T))
convert{T}(::Type{Factorization{T}}, A::QRCompactWY) = convert(QRCompactWY{T}, A)
convert{T}(::Type{QRPivoted{T}},A::QRPivoted) = QRPivoted(convert(AbstractMatrix{T}, A.factors), convert(Vector{T}, A.τ), A.jpvt)
convert{T}(::Type{Factorization{T}}, A::QRPivoted) = convert(QRPivoted{T}, A)

function getindex(A::QR, d::Symbol)
    m, n = size(A)
    d == :R && return triu!(A.factors[1:min(m,n), 1:n])
    d == :Q && return QRPackedQ(A.factors,A.τ)
    throw(KeyError(d))
end
function getindex(A::QRCompactWY, d::Symbol)
    m, n = size(A)
    d == :R && return triu!(A.factors[1:min(m,n), 1:n])
    d == :Q && return QRCompactWYQ(A.factors,A.T)
    throw(KeyError(d))
end
function getindex{T}(A::QRPivoted{T}, d::Symbol)
    m, n = size(A)
    d == :R && return triu!(A.factors[1:min(m,n), 1:n])
    d == :Q && return QRPackedQ(A.factors,A.τ)
    d == :p && return A.jpvt
    if d == :P
        p = A[:p]
        n = length(p)
        P = zeros(T, n, n)
        for i in 1:n
            P[p[i],i] = one(T)
        end
        return P
    end
    throw(KeyError(d))
end
# Type-stable interface to get Q
getq(A::QRCompactWY) = QRCompactWYQ(A.factors,A.T)
getq(A::QRPivoted) = QRPackedQ(A.factors,A.τ)

immutable QRPackedQ{T,S<:AbstractMatrix} <: AbstractMatrix{T}
    factors::S
    τ::Vector{T}
    QRPackedQ(factors::AbstractMatrix{T}, τ::Vector{T}) = new(factors, τ)
end
QRPackedQ{T}(factors::AbstractMatrix{T}, τ::Vector{T}) = QRPackedQ{T,typeof(factors)}(factors, τ)

immutable QRPackedWYQ{S,M<:AbstractMatrix} <: AbstractMatrix{S}
    factors::M
    T::Matrix{S}
    QRPackedWYQ(factors::AbstractMatrix{S}, T::Matrix{S}) = new(factors, T)
end
QRPackedWYQ{S}(factors::AbstractMatrix{S}, T::Matrix{S}) = QRPackedWYQ{S,typeof(factors)}(factors, T)

immutable QRCompactWYQ{S, M<:AbstractMatrix} <: AbstractMatrix{S}
    factors::M
    T::Matrix{S}
    QRCompactWYQ(factors::AbstractMatrix{S}, T::Matrix{S}) = new(factors, T)
end
QRCompactWYQ{S}(factors::AbstractMatrix{S}, T::Matrix{S}) = QRCompactWYQ{S,typeof(factors)}(factors, T)

convert{T}(::Type{QRPackedQ{T}}, Q::QRPackedQ) = QRPackedQ(convert(AbstractMatrix{T}, Q.factors), convert(Vector{T}, Q.τ))
convert{T}(::Type{AbstractMatrix{T}}, Q::QRPackedQ) = convert(QRPackedQ{T}, Q)
convert{S}(::Type{QRCompactWYQ{S}}, Q::QRCompactWYQ) = QRCompactWYQ(convert(AbstractMatrix{S}, Q.factors), convert(AbstractMatrix{S}, Q.T))
convert{S}(::Type{AbstractMatrix{S}}, Q::QRCompactWYQ) = convert(QRCompactWYQ{S}, Q)

size(A::Union(QR,QRCompactWY,QRPivoted), dim::Integer) = size(A.factors, dim)
size(A::Union(QR,QRCompactWY,QRPivoted)) = size(A.factors)
size(A::Union(QRPackedQ,QRCompactWYQ), dim::Integer) = 0 < dim ? (dim <= 2 ? size(A.factors, 1) : 1) : throw(BoundsError())
size(A::Union(QRPackedQ,QRCompactWYQ)) = size(A, 1), size(A, 2)

full{T}(A::Union(QRPackedQ{T},QRCompactWYQ{T}); thin::Bool=true) = A_mul_B!(A, thin ? eye(T, size(A.factors,1), minimum(size(A.factors))) : eye(T, size(A.factors,1)))

## Multiplication by Q
### QB
A_mul_B!{T<:BlasFloat}(A::QRCompactWYQ{T}, B::StridedVecOrMat{T}) = LAPACK.gemqrt!('L','N',A.factors,A.T,B)
A_mul_B!{T<:BlasFloat}(A::QRPackedQ{T}, B::StridedVecOrMat{T}) = LAPACK.ormqr!('L','N',A.factors,A.τ,B)
function A_mul_B!{T}(A::QRPackedQ{T}, B::AbstractVecOrMat{T})
    mA, nA = size(A.factors)
    mB, nB = size(B,1), size(B,2)
    mA == mB || throw(DimensionMismatch())
    Afactors = A.factors
    @inbounds begin
        for k = min(mA,nA):-1:1
            for j = 1:nB
                vBj = B[k,j]
                for i = k+1:mB
                    vBj += conj(Afactors[i,k])*B[i,j]
                end
                vBj = A.τ[k]*vBj
                B[k,j] -= vBj
                for i = k+1:mB
                    B[i,j] -= Afactors[i,k]*vBj
                end
            end
        end
    end
    B
end

function (*){TA,Tb}(A::Union(QRPackedQ{TA},QRCompactWYQ{TA}), b::StridedVector{Tb})
    TAb = promote_type(TA, Tb)
    Anew = convert(AbstractMatrix{TAb}, A)
    if size(A.factors, 1) == length(b)
        bnew = copy_oftype(b, TAb)
    elseif size(A.factors, 2) == length(b)
        bnew = [b; zeros(TAb, size(A.factors, 1) - length(b))]
    else
        throw(DimensionMismatch("vector must have length either $(size(A.factors, 1)) or $(size(A.factors, 2))"))
    end
    A_mul_B!(Anew, bnew)
end
function (*){TA,TB}(A::Union(QRPackedQ{TA},QRCompactWYQ{TA}), B::StridedMatrix{TB})
    TAB = promote_type(TA, TB)
    Anew = convert(AbstractMatrix{TAB}, A)
    if size(A.factors, 1) == size(B, 1)
        Bnew = copy_oftype(B, TAB)
    elseif size(A.factors, 2) == size(B, 1)
        Bnew = [B; zeros(TAB, size(A.factors, 1) - size(B,1), size(B, 2))]
    else
        throw(DimensionMismatch("first dimension of matrix must have size either $(size(A.factors, 1)) or $(size(A.factors, 2))"))
    end
    A_mul_B!(Anew, Bnew)
end

### QcB
Ac_mul_B!{T<:BlasReal}(A::QRCompactWYQ{T}, B::StridedVecOrMat{T}) = LAPACK.gemqrt!('L','T',A.factors,A.T,B)
Ac_mul_B!{T<:BlasComplex}(A::QRCompactWYQ{T}, B::StridedVecOrMat{T}) = LAPACK.gemqrt!('L','C',A.factors,A.T,B)
Ac_mul_B!{T<:BlasReal}(A::QRPackedQ{T}, B::StridedVecOrMat{T}) = LAPACK.ormqr!('L','T',A.factors,A.τ,B)
Ac_mul_B!{T<:BlasComplex}(A::QRPackedQ{T}, B::StridedVecOrMat{T}) = LAPACK.ormqr!('L','C',A.factors,A.τ,B)
function Ac_mul_B!{T}(A::QRPackedQ{T}, B::AbstractVecOrMat{T})
    mA, nA = size(A.factors)
    mB, nB = size(B,1), size(B,2)
    mA == mB || throw(DimensionMismatch())
    Afactors = A.factors
    @inbounds begin
        for k = 1:min(mA,nA)
            for j = 1:nB
                vBj = B[k,j]
                for i = k+1:mB
                    vBj += conj(Afactors[i,k])*B[i,j]
                end
                vBj = conj(A.τ[k])*vBj
                B[k,j] -= vBj
                for i = k+1:mB
                    B[i,j] -= Afactors[i,k]*vBj
                end
            end
        end
    end
    B
end
function Ac_mul_B{TQ<:Number,TB<:Number,N}(Q::Union(QRPackedQ{TQ},QRCompactWYQ{TQ}), B::StridedArray{TB,N})
    TQB = promote_type(TQ,TB)
    return Ac_mul_B!(convert(AbstractMatrix{TQB}, Q), copy_oftype(B, TQB))
end

### AQ
A_mul_B!{T<:BlasFloat}(A::StridedVecOrMat{T}, B::QRCompactWYQ{T}) = LAPACK.gemqrt!('R','N', B.factors, B.T, A)
A_mul_B!(A::StridedVecOrMat, B::QRPackedQ) = LAPACK.ormqr!('R', 'N', B.factors, B.τ, A)
function A_mul_B!{T}(A::StridedMatrix{T},Q::QRPackedQ{T})
    mQ, nQ = size(Q.factors)
    mA, nA = size(A,1), size(A,2)
    nA == mQ || throw(DimensionMismatch())
    Qfactors = Q.factors
    @inbounds begin
        for k = 1:min(mQ,nQ)
            for i = 1:mA
                vAi = A[i,k]
                for j = k+1:mQ
                    vAi += A[i,j]*Qfactors[j,k]
                end
                vAi = vAi*Q.τ[k]
                A[i,k] -= vAi
                for j = k+1:nA
                    A[i,j] -= vAi*conj(Qfactors[j,k])
                end
            end
        end
    end
    A
end

function (*){TA,TQ,N}(A::StridedArray{TA,N}, Q::Union(QRPackedQ{TQ},QRCompactWYQ{TQ}))
    TAQ = promote_type(TA, TQ)
    return A_mul_B!(copy_oftype(A, TAQ), convert(AbstractMatrix{TAQ}, Q))
end

### AQc
A_mul_Bc!{T<:BlasReal}(A::StridedVecOrMat{T}, B::QRCompactWYQ{T}) = LAPACK.gemqrt!('R','T',B.factors,B.T,A)
A_mul_Bc!{T<:BlasComplex}(A::StridedVecOrMat{T}, B::QRCompactWYQ{T}) = LAPACK.gemqrt!('R','C',B.factors,B.T,A)
A_mul_Bc!{T<:BlasReal}(A::StridedVecOrMat{T}, B::QRPackedQ{T}) = LAPACK.ormqr!('R','T',B.factors,B.τ,A)
A_mul_Bc!{T<:BlasComplex}(A::StridedVecOrMat{T}, B::QRPackedQ{T}) = LAPACK.ormqr!('R','C',B.factors,B.τ,A)
function A_mul_Bc!{T}(A::AbstractMatrix{T},Q::QRPackedQ{T})
    mQ, nQ = size(Q.factors)
    mA, nA = size(A,1), size(A,2)
    nA == mQ || throw(DimensionMismatch())
    Qfactors = Q.factors
    @inbounds begin
        for k = min(mQ,nQ):-1:1
            for i = 1:mA
                vAi = A[i,k]
                for j = k+1:mQ
                    vAi += A[i,j]*Qfactors[j,k]
                end
                vAi = vAi*conj(Q.τ[k])
                A[i,k] -= vAi
                for j = k+1:nA
                    A[i,j] -= vAi*conj(Qfactors[j,k])
                end
            end
        end
    end
    A
end
A_mul_Bc(A::AbstractTriangular, B::Union(QRCompactWYQ,QRPackedQ)) = A_mul_Bc(full(A), B)
function A_mul_Bc{TA,TB}(A::AbstractArray{TA}, B::Union(QRCompactWYQ{TB},QRPackedQ{TB}))
    TAB = promote_type(TA,TB)
    BB = convert(AbstractMatrix{TAB}, B)
    if size(A,2) == size(B.factors, 1)
        return A_mul_Bc!(copy_oftype(A, TAB), BB)
    elseif size(A,2) == size(B.factors,2)
        return A_mul_Bc!([A zeros(TAB, size(A, 1), size(B.factors, 1) - size(B.factors, 2))], BB)
    else
        throw(DimensionMismatch())
    end
end

A_ldiv_B!{T<:BlasFloat}(A::QRCompactWY{T}, b::StridedVector{T}) = (A_ldiv_B!(UpperTriangular(A[:R]), sub(Ac_mul_B!(A[:Q], b), 1:size(A, 2))); b)
A_ldiv_B!{T<:BlasFloat}(A::QRCompactWY{T}, B::StridedMatrix{T}) = (A_ldiv_B!(UpperTriangular(A[:R]), sub(Ac_mul_B!(A[:Q], B), 1:size(A, 2), 1:size(B, 2))); B)

# Julia implementation similarly to xgelsy
function A_ldiv_B!{T<:BlasFloat}(A::QRPivoted{T}, B::StridedMatrix{T}, rcond::Real)
    mA, nA = size(A.factors)
    nr = min(mA,nA)
    nrhs = size(B, 2)
    if nr == 0 return zeros(T, 0, nrhs), 0 end
    ar = abs(A.factors[1])
    if ar == 0 return zeros(T, nr, nrhs), 0 end
    rnk = 1
    xmin = ones(T, 1)
    xmax = ones(T, 1)
    tmin = tmax = ar
    while rnk < nr
        tmin, smin, cmin = LAPACK.laic1!(2, xmin, tmin, sub(A.factors, 1:rnk, rnk + 1), A.factors[rnk + 1, rnk + 1])
        tmax, smax, cmax = LAPACK.laic1!(1, xmax, tmax, sub(A.factors, 1:rnk, rnk + 1), A.factors[rnk + 1, rnk + 1])
        tmax*rcond > tmin && break
        push!(xmin, cmin)
        push!(xmax, cmax)
        for i = 1:rnk
            xmin[i] *= smin
            xmax[i] *= smax
        end
        rnk += 1
    end
    C, τ = LAPACK.tzrzf!(A.factors[1:rnk,:])
    A_ldiv_B!(UpperTriangular(C[1:rnk,1:rnk]),sub(Ac_mul_B!(getq(A),sub(B, 1:mA, 1:nrhs)),1:rnk,1:nrhs))
    B[rnk+1:end,:] = zero(T)
    LAPACK.ormrz!('L', iseltype(B, Complex) ? 'C' : 'T', C, τ, sub(B,1:nA,1:nrhs))
    B[1:nA,:] = sub(B, 1:nA, :)[invperm(A[:p]::Vector{BlasInt}),:]
    return B, rnk
end
A_ldiv_B!{T<:BlasFloat}(A::QRPivoted{T}, B::StridedVector{T}) = vec(A_ldiv_B!(A,reshape(B,length(B),1)))
A_ldiv_B!{T<:BlasFloat}(A::QRPivoted{T}, B::StridedVecOrMat{T}) = A_ldiv_B!(A, B, maximum(size(A))*eps(real(float(one(eltype(B))))))[1]
function A_ldiv_B!{T}(A::QR{T},B::StridedMatrix{T})
    m, n = size(A)
    minmn = min(m,n)
    mB, nB = size(B)
    Ac_mul_B!(A[:Q],sub(B,1:m,1:nB)) # Reconsider when arrayviews are merged.
    R = A[:R]
    @inbounds begin
        if n > m # minimum norm solution
            τ = zeros(T,m)
            for k = m:-1:1 # Trapezoid to triangular by elementary operation
                τ[k] = elementaryRightTrapezoid!(R,k)
                for i = 1:k-1
                    vRi = R[i,k]
                    for j = m+1:n
                        vRi += R[i,j]*R[k,j]
                    end
                    vRi *= τ[k]
                    R[i,k] -= vRi
                    for j = m+1:n
                        R[i,j] -= vRi*R[k,j]
                    end
                end
            end
        end
        for k = 1:nB # solve triangular system. When array views are implemented, consider exporting    to function.
            for i = minmn:-1:1
                for j = i+1:minmn
                    B[i,k] -= R[i,j]*B[j,k]
                end
                B[i,k] /= R[i,i]
            end
        end
        if n > m # Apply elementary transformation to solution
            B[m+1:mB,1:nB] = zero(T)
            for j = 1:nB
                for k = 1:m
                    vBj = B[k,j]
                    for i = m+1:n
                        vBj += B[i,j]*conj(R[k,i])
                    end
                    vBj *= τ[k]
                    B[k,j] -= vBj
                    for i = m+1:n
                        B[i,j] -= R[k,i]*vBj
                    end
                end
            end
        end
    end
    return B
end
A_ldiv_B!(A::QR, B::StridedVector) = A_ldiv_B!(A, reshape(B, length(B), 1))[:]
function A_ldiv_B!(A::QRPivoted, b::StridedVector)
    A_ldiv_B!(QR(A.factors,A.τ), b)
    b[1:size(A.factors, 2)] = sub(b, 1:size(A.factors, 2))[invperm(A.jpvt)]
    b
end
function A_ldiv_B!(A::QRPivoted, B::StridedMatrix)
    A_ldiv_B!(QR(A.factors, A.τ), B)
    B[1:size(A.factors, 2),:] = sub(B, 1:size(A.factors, 2), :)[invperm(A.jpvt)]
    B
end
function \{TA,Tb}(A::Union(QR{TA},QRCompactWY{TA},QRPivoted{TA}), b::StridedVector{Tb})
    S = promote_type(TA,Tb)
    m,n = size(A)
    m == length(b) || throw(DimensionMismatch("left hand side has $m rows, but right hand side has length $(length(b))"))
    AA = convert(Factorization{S}, A)
    if n > m
        x = A_ldiv_B!(AA, [b; zeros(S, n - m)])
    else
        x = A_ldiv_B!(AA, copy_oftype(b, S))
    end
    return length(x) > n ? x[1:n] : x
end
function \{TA,TB}(A::Union(QR{TA},QRCompactWY{TA},QRPivoted{TA}),B::StridedMatrix{TB})
    S = promote_type(TA,TB)
    m,n = size(A)
    m == size(B,1) || throw(DimensionMismatch("left hand side has $m rows, but right hand side has $(size(B,1)) rows"))
    AA = convert(Factorization{S}, A)
    if n > m
        X = A_ldiv_B!(AA, [B; zeros(S, n - m, size(B, 2))])
    else
        X = A_ldiv_B!(AA, copy_oftype(B, S))
    end
    return size(X, 1) > n ? X[1:n,:] : X
end

##TODO:  Add methods for rank(A::QRP{T}) and adjust the (\) method accordingly
##       Add rcond methods for Cholesky, LU, QR and QRP types
## Lower priority: Add LQ, QL and RQ factorizations

# FIXME! Should add balancing option through xgebal
immutable Hessenberg{T,S<:AbstractMatrix} <: Factorization{T}
    factors::S
    τ::Vector{T}
    Hessenberg(factors::AbstractMatrix{T}, τ::Vector{T}) = new(factors, τ)
end
Hessenberg{T}(factors::AbstractMatrix{T}, τ::Vector{T}) = Hessenberg{T,typeof(factors)}(factors, τ)

Hessenberg(A::StridedMatrix) = Hessenberg(LAPACK.gehrd!(A)...)

hessfact!{T<:BlasFloat}(A::StridedMatrix{T}) = Hessenberg(A)
hessfact{T<:BlasFloat}(A::StridedMatrix{T}) = hessfact!(copy(A))
function hessfact{T}(A::StridedMatrix{T})
    S = promote_type(Float32, typeof(one(T)/norm(one(T))))
    return hessfact!(copy_oftype(A, S))
end

immutable HessenbergQ{T,S<:AbstractMatrix} <: AbstractMatrix{T}
    factors::S
    τ::Vector{T}
    HessenbergQ(factors::AbstractMatrix{T}, τ::Vector{T}) = new(factors, τ)
end
HessenbergQ{T}(factors::AbstractMatrix{T}, τ::Vector{T}) = HessenbergQ{T,typeof(factors)}(factors, τ)
HessenbergQ(A::Hessenberg) = HessenbergQ(A.factors, A.τ)
size(A::HessenbergQ, args...) = size(A.factors, args...)

function getindex(A::Hessenberg, d::Symbol)
    d == :Q && return HessenbergQ(A)
    d == :H && return triu(A.factors, -1)
    throw(KeyError(d))
end

full(A::HessenbergQ) = LAPACK.orghr!(1, size(A.factors, 1), copy(A.factors), A.τ)

# Also printing of QRQs
getindex(A::Union(QRPackedQ,QRCompactWYQ,HessenbergQ), i::Integer, j::Integer) = (x = zeros(eltype(A), size(A, 1)); x[i] = 1; y = zeros(eltype(A), size(A, 2)); y[j] = 1; dot(x, A*y))


#######################
# Eigendecompositions #
#######################

# Eigenvalues
immutable Eigen{T,V,S<:AbstractMatrix,U<:AbstractVector} <: Factorization{T}
    values::U
    vectors::S
    Eigen(values::AbstractVector{V}, vectors::AbstractMatrix{T}) = new(values, vectors)
end
Eigen{T,V}(values::AbstractVector{V}, vectors::AbstractMatrix{T}) = Eigen{T,V,typeof(vectors),typeof(values)}(values, vectors)

# Generalized eigenvalue problem.
immutable GeneralizedEigen{T,V,S<:AbstractMatrix,U<:AbstractVector} <: Factorization{T}
    values::U
    vectors::S
    GeneralizedEigen(values::AbstractVector{V}, vectors::AbstractMatrix{T}) = new(values, vectors)
end
GeneralizedEigen{T,V}(values::AbstractVector{V}, vectors::AbstractMatrix{T}) = GeneralizedEigen{T,V,typeof(vectors),typeof(values)}(values, vectors)


function getindex(A::Union(Eigen,GeneralizedEigen), d::Symbol)
    d == :values && return A.values
    d == :vectors && return A.vectors
    throw(KeyError(d))
end

isposdef(A::Union(Eigen,GeneralizedEigen)) = all(A.values .> 0)

function eigfact!{T<:BlasReal}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    n = size(A, 2)
    n==0 && return Eigen(zeros(T, 0), zeros(T, 0, 0))
    issym(A) && return eigfact!(Symmetric(A))
    A, WR, WI, VL, VR, _ = LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'V', 'N', A)
    all(WI .== 0.) && return Eigen(WR, VR)
    evec = zeros(Complex{T}, n, n)
    j = 1
    while j <= n
        if WI[j] == 0.0
            evec[:,j] = VR[:,j]
        else
            evec[:,j]   = VR[:,j] + im*VR[:,j+1]
            evec[:,j+1] = VR[:,j] - im*VR[:,j+1]
            j += 1
        end
        j += 1
    end
    return Eigen(complex(WR, WI), evec)
end

function eigfact!{T<:BlasComplex}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    n = size(A, 2)
    n == 0 && return Eigen(zeros(T, 0), zeros(T, 0, 0))
    ishermitian(A) && return eigfact!(Hermitian(A))
    return Eigen(LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'V', 'N', A)[[2,4]]...)
end
function eigfact{T}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    S = promote_type(Float32, typeof(one(T)/norm(one(T))))
    eigfact!(copy_oftype(A, S), permute = permute, scale = scale)
end
eigfact(x::Number) = Eigen([x], fill(one(x), 1, 1))

# function eig(A::Union(Number, AbstractMatrix); permute::Bool=true, scale::Bool=true)
#     F = eigfact(A, permute=permute, scale=scale)
#     F[:values], F[:vectors]
# end
function eig(A::Union(Number, AbstractMatrix), args...; kwargs...)
    F = eigfact(A, args...; kwargs...)
    F[:values], F[:vectors]
end
#Calculates eigenvectors
eigvecs(A::Union(Number, AbstractMatrix), args...; kwargs...) = eigfact(A, args...; kwargs...)[:vectors]

function eigvals!{T<:BlasReal}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    issym(A) && return eigvals!(Symmetric(A))
    _, valsre, valsim, _ = LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'N', 'N', A)
    return all(valsim .== 0) ? valsre : complex(valsre, valsim)
end
function eigvals!{T<:BlasComplex}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    ishermitian(A) && return eigvals(Hermitian(A))
    return LAPACK.geevx!(permute ? (scale ? 'B' : 'P') : (scale ? 'S' : 'N'), 'N', 'N', 'N', A)[2]
end
function eigvals{T}(A::StridedMatrix{T}; permute::Bool=true, scale::Bool=true)
    S = promote_type(Float32, typeof(one(T)/norm(one(T))))
    return eigvals!(copy_oftype(A, S), permute = permute, scale = scale)
end
function eigvals{T<:Number}(x::T; kwargs...)
    val = convert(promote_type(Float32, typeof(one(T)/norm(one(T)))), x)
    return imag(val) == 0 ? [real(val)] : [val]
end

#Computes maximum and minimum eigenvalue
function eigmax(A::Union(Number, StridedMatrix); permute::Bool=true, scale::Bool=true)
    v = eigvals(A, permute = permute, scale = scale)
    iseltype(v,Complex) ? error("DomainError: complex eigenvalues cannot be ordered") : maximum(v)
end
function eigmin(A::Union(Number, StridedMatrix); permute::Bool=true, scale::Bool=true)
    v = eigvals(A, permute = permute, scale = scale)
    iseltype(v,Complex) ? error("DomainError: complex eigenvalues cannot be ordered") : minimum(v)
end

inv(A::Eigen) = A.vectors/Diagonal(A.values)*A.vectors'
det(A::Eigen) = prod(A.values)

# Generalized eigenproblem
function eigfact!{T<:BlasReal}(A::StridedMatrix{T}, B::StridedMatrix{T})
    issym(A) && isposdef(B) && return eigfact!(Symmetric(A), Symmetric(B))
    n = size(A, 1)
    alphar, alphai, beta, _, vr = LAPACK.ggev!('N', 'V', A, B)
    all(alphai .== 0) && return GeneralizedEigen(alphar ./ beta, vr)

    vecs = zeros(Complex{T}, n, n)
    j = 1
    while j <= n
        if alphai[j] == 0.0
            vecs[:,j] = vr[:,j]
        else
            vecs[:,j  ] = vr[:,j] + im*vr[:,j+1]
            vecs[:,j+1] = vr[:,j] - im*vr[:,j+1]
            j += 1
        end
        j += 1
    end
    return GeneralizedEigen(complex(alphar, alphai)./beta, vecs)
end

function eigfact!{T<:BlasComplex}(A::StridedMatrix{T}, B::StridedMatrix{T})
    ishermitian(A) && isposdef(B) && return eigfact!(Hermitian(A), Hermitian(B))
    alpha, beta, _, vr = LAPACK.ggev!('N', 'V', A, B)
    return GeneralizedEigen(alpha./beta, vr)
end
function eigfact{TA,TB}(A::AbstractMatrix{TA}, B::AbstractMatrix{TB})
    S = promote_type(Float32, typeof(one(TA)/norm(one(TA))),TB)
    return eigfact!(copy_oftype(A, S), copy_oftype(B, S))
end

function eigvals!{T<:BlasReal}(A::StridedMatrix{T}, B::StridedMatrix{T})
    issym(A) && isposdef(B) && return eigvals!(Symmetric(A), Symmetric(B))
    alphar, alphai, beta, vl, vr = LAPACK.ggev!('N', 'N', A, B)
    return (all(alphai .== 0) ? alphar : complex(alphar, alphai))./beta
end
function eigvals!{T<:BlasComplex}(A::StridedMatrix{T}, B::StridedMatrix{T})
    ishermitian(A) && isposdef(B) && return eigvals!(Hermitian(A), Hermitian(B))
    alpha, beta, vl, vr = LAPACK.ggev!('N', 'N', A, B)
    alpha./beta
end
function eigvals{TA,TB}(A::AbstractMatrix{TA}, B::AbstractMatrix{TB})
    S = promote_type(Float32, typeof(one(TA)/norm(one(TA))),TB)
    return eigvals!(copy_oftype(A, S), copy_oftype(B, S))
end

# SVD
immutable SVD{T<:BlasFloat,Tr,M<:AbstractArray} <: Factorization{T}
    U::M
    S::Vector{Tr}
    Vt::M
    SVD(U::AbstractArray{T}, S::Vector{Tr}, Vt::AbstractArray{T}) = new(U, S, Vt)
end
SVD{T<:BlasFloat,Tr}(U::AbstractArray{T}, S::Vector{Tr}, Vt::AbstractArray{T}) = SVD{T,Tr,typeof(U)}(U, S, Vt)

function svdfact!{T<:BlasFloat}(A::StridedMatrix{T}; thin::Bool=true)
    m,n = size(A)
    if m == 0 || n == 0
        u,s,vt = (eye(T, m, thin ? n : m), real(zeros(T,0)), eye(T,n,n))
    else
        u,s,vt = LAPACK.gesdd!(thin ? 'S' : 'A', A)
    end
    SVD(u,s,vt)
end
function svdfact{T}(A::StridedVecOrMat{T};thin = true)
    S = promote_type(Float32, typeof(one(T)/norm(one(T))))
    svdfact!(copy_oftype(A, S), thin = thin)
end
svdfact(x::Number; thin::Bool=true) = SVD(x == 0 ? fill(one(x), 1, 1) : fill(x/abs(x), 1, 1), [abs(x)], fill(one(x), 1, 1))
svdfact(x::Integer; thin::Bool=true) = svdfact(float(x), thin=thin)

function svd(A::Union(Number, AbstractArray); thin::Bool=true)
    F = svdfact(A, thin=thin)
    F.U, F.S, F.Vt'
end

function getindex(F::SVD, d::Symbol)
    d == :U && return F.U
    d == :S && return F.S
    d == :Vt && return F.Vt
    d == :V && return F.Vt'
    throw(KeyError(d))
end

svdvals!{T<:BlasFloat}(A::StridedMatrix{T}) = any([size(A)...].==0) ? zeros(T, 0) : LAPACK.gesdd!('N', A)[2]
svdvals{T<:BlasFloat}(A::AbstractMatrix{T}) = svdvals!(copy(A))
function svdvals{T}(A::AbstractMatrix{T})
    S = promote_type(Float32, typeof(one(T)/norm(one(T))))
    svdvals!(copy_oftype(A, S))
end
svdvals(x::Number) = [abs(x)]

# SVD least squares
function \{T<:BlasFloat}(A::SVD{T}, B::StridedVecOrMat{T})
    n = length(A.S)
    Sinv = zeros(T, n)
    k = length(find(A.S .> eps(real(float(one(T))))*maximum(A.S)))
    Sinv[1:k] = one(T) ./ A.S[1:k]
    A.Vt[1:k,:]' * (Sinv[1:k] .* (A.U[:,1:k]' * B))
end

# Generalized svd
immutable GeneralizedSVD{T,S} <: Factorization{T}
    U::S
    V::S
    Q::S
    a::Vector
    b::Vector
    k::Int
    l::Int
    R::S
    GeneralizedSVD(U::AbstractMatrix{T}, V::AbstractMatrix{T}, Q::AbstractMatrix{T}, a::Vector, b::Vector, k::Int, l::Int, R::AbstractMatrix{T}) = new(U, V, Q, a, b, k, l, R)
end
GeneralizedSVD{T}(U::AbstractMatrix{T}, V::AbstractMatrix{T}, Q::AbstractMatrix{T}, a::Vector, b::Vector, k::Int, l::Int, R::AbstractMatrix{T}) = GeneralizedSVD{T,typeof(U)}(U, V, Q, a, b, k, l, R)

function svdfact!{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T})
    U, V, Q, a, b, k, l, R = LAPACK.ggsvd!('U', 'V', 'Q', A, B)
    GeneralizedSVD(U, V, Q, a, b, Int(k), Int(l), R)
end
svdfact{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T}) = svdfact!(copy(A),copy(B))
function svdfact{TA,TB}(A::StridedMatrix{TA}, B::StridedMatrix{TB})
    S = promote_type(Float32, typeof(one(TA)/norm(one(TA))),TB)
    return svdfact!(copy_oftype(A, S), copy_oftype(B, S))
end

function svd(A::AbstractMatrix, B::AbstractMatrix)
    F = svdfact(A, B)
    F[:U], F[:V], F[:Q], F[:D1], F[:D2], F[:R0]
end

function getindex{T}(obj::GeneralizedSVD{T}, d::Symbol)
    d == :U && return obj.U
    d == :V && return obj.V
    d == :Q && return obj.Q
    (d == :alpha || d == :a) && return obj.a
    (d == :beta || d == :b) && return obj.b
    (d == :vals || d == :S) && return obj.a[1:obj.k + obj.l] ./ obj.b[1:obj.k + obj.l]
    if d == :D1
        m = size(obj.U, 1)
        if m - obj.k - obj.l >= 0
            return [eye(T, obj.k) zeros(T, obj.k, obj.l); zeros(T, obj.l, obj.k) diagm(obj.a[obj.k + 1:obj.k + obj.l]); zeros(T, m - obj.k - obj.l, obj.k + obj.l)]
        else
            return [eye(T, m, obj.k) [zeros(T, obj.k, m - obj.k); diagm(obj.a[obj.k + 1:m])] zeros(T, m, obj.k + obj.l - m)]
        end
    end
    if d == :D2
        m = size(obj.U, 1)
        p = size(obj.V, 1)
        if m - obj.k - obj.l >= 0
            return [zeros(T, obj.l, obj.k) diagm(obj.b[obj.k + 1:obj.k + obj.l]); zeros(T, p - obj.l, obj.k + obj.l)]
        else
            return [zeros(T, p, obj.k) [diagm(obj.b[obj.k + 1:m]); zeros(T, obj.k + p - m, m - obj.k)] [zeros(T, m - obj.k, obj.k + obj.l - m); eye(T, obj.k + p - m, obj.k + obj.l - m)]]
        end
    end
    d == :R && return obj.R
    if d == :R0
        n = size(obj.Q, 1)
        return [zeros(T, obj.k + obj.l, n - obj.k - obj.l) obj.R]
    end
    throw(KeyError(d))
end

function svdvals!{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T})
    _, _, _, a, b, k, l, _ = LAPACK.ggsvd!('N', 'N', 'N', A, B)
    a[1:k + l] ./ b[1:k + l]
end
svdvals{T<:BlasFloat}(A::StridedMatrix{T},B::StridedMatrix{T}) = svdvals!(copy(A),copy(B))
function svdvals{TA,TB}(A::StridedMatrix{TA}, B::StridedMatrix{TB})
    S = promote_type(Float32, typeof(one(TA)/norm(one(TA))), TB)
    return svdvals!(copy_oftype(A, S), copy_oftype(B, S))
end

immutable Schur{Ty<:BlasFloat, S<:AbstractMatrix} <: Factorization{Ty}
    T::S
    Z::S
    values::Vector
    Schur(T::AbstractMatrix{Ty}, Z::AbstractMatrix{Ty}, values::Vector) = new(T, Z, values)
end
Schur{Ty}(T::AbstractMatrix{Ty}, Z::AbstractMatrix{Ty}, values::Vector) = Schur{Ty, typeof(T)}(T, Z, values)

schurfact!{T<:BlasFloat}(A::StridedMatrix{T}) = Schur(LinAlg.LAPACK.gees!('V', A)...)
schurfact{T<:BlasFloat}(A::StridedMatrix{T}) = schurfact!(copy(A))
function schurfact{T}(A::StridedMatrix{T})
    S = promote_type(Float32, typeof(one(T)/norm(one(T))))
    return schurfact!(copy_oftype(A, S))
end

function getindex(F::Schur, d::Symbol)
    (d == :T || d == :Schur) && return F.T
    (d == :Z || d == :vectors) && return F.Z
    d == :values && return F.values
    throw(KeyError(d))
end

function schur(A::StridedMatrix)
    SchurF = schurfact(A)
    SchurF[:T], SchurF[:Z], SchurF[:values]
end

ordschur!{Ty<:BlasFloat}(Q::StridedMatrix{Ty}, T::StridedMatrix{Ty}, select::Union(Vector{Bool},BitVector)) = Schur(LinAlg.LAPACK.trsen!(convert(Vector{BlasInt}, select), T , Q)...)
ordschur{Ty<:BlasFloat}(Q::StridedMatrix{Ty}, T::StridedMatrix{Ty}, select::Union(Vector{Bool},BitVector)) = ordschur!(copy(Q), copy(T), select)
ordschur!{Ty<:BlasFloat}(schur::Schur{Ty}, select::Union(Vector{Bool},BitVector)) = (res=ordschur!(schur.Z, schur.T, select); schur[:values][:]=res[:values]; res)
ordschur{Ty<:BlasFloat}(schur::Schur{Ty}, select::Union(Vector{Bool},BitVector)) = ordschur(schur.Z, schur.T, select)

immutable GeneralizedSchur{Ty<:BlasFloat, M<:AbstractMatrix} <: Factorization{Ty}
    S::M
    T::M
    alpha::Vector
    beta::Vector{Ty}
    Q::M
    Z::M
    GeneralizedSchur(S::AbstractMatrix{Ty}, T::AbstractMatrix{Ty}, alpha::Vector, beta::Vector{Ty}, Q::AbstractMatrix{Ty}, Z::AbstractMatrix{Ty}) = new(S, T, alpha, beta, Q, Z)
end
GeneralizedSchur{Ty}(S::AbstractMatrix{Ty}, T::AbstractMatrix{Ty}, alpha::Vector, beta::Vector{Ty}, Q::AbstractMatrix{Ty}, Z::AbstractMatrix{Ty}) = GeneralizedSchur{Ty, typeof(S)}(S, T, alpha, beta, Q, Z)

schurfact!{T<:BlasFloat}(A::StridedMatrix{T}, B::StridedMatrix{T}) = GeneralizedSchur(LinAlg.LAPACK.gges!('V', 'V', A, B)...)
schurfact{T<:BlasFloat}(A::StridedMatrix{T},B::StridedMatrix{T}) = schurfact!(copy(A),copy(B))
function schurfact{TA,TB}(A::StridedMatrix{TA}, B::StridedMatrix{TB})
    S = promote_type(Float32, typeof(one(TA)/norm(one(TA))), TB)
    return schurfact!(copy_oftype(A, S), copy_oftype(B, S))
end

ordschur!{Ty<:BlasFloat}(S::StridedMatrix{Ty}, T::StridedMatrix{Ty}, Q::StridedMatrix{Ty}, Z::StridedMatrix{Ty}, select::Union(Vector{Bool},BitVector)) = GeneralizedSchur(LinAlg.LAPACK.tgsen!(convert(Vector{BlasInt}, select), S, T, Q, Z)...)
ordschur{Ty<:BlasFloat}(S::StridedMatrix{Ty}, T::StridedMatrix{Ty}, Q::StridedMatrix{Ty}, Z::StridedMatrix{Ty}, select::Union(Vector{Bool},BitVector)) = ordschur!(copy(S), copy(T), copy(Q), copy(Z), select)
ordschur!{Ty<:BlasFloat}(gschur::GeneralizedSchur{Ty}, select::Union(Vector{Bool},BitVector)) = (res=ordschur!(gschur.S, gschur.T, gschur.Q, gschur.Z, select); gschur[:alpha][:]=res[:alpha]; gschur[:beta][:]=res[:beta]; res)
ordschur{Ty<:BlasFloat}(gschur::GeneralizedSchur{Ty}, select::Union(Vector{Bool},BitVector)) = ordschur(gschur.S, gschur.T, gschur.Q, gschur.Z, select)

function getindex(F::GeneralizedSchur, d::Symbol)
    d == :S && return F.S
    d == :T && return F.T
    d == :alpha && return F.alpha
    d == :beta && return F.beta
    d == :values && return F.alpha./F.beta
    (d == :Q || d == :left) && return F.Q
    (d == :Z || d == :right) && return F.Z
    throw(KeyError(d))
end

function schur(A::StridedMatrix, B::StridedMatrix)
    SchurF = schurfact(A, B)
    SchurF[:S], SchurF[:T], SchurF[:Q], SchurF[:Z]
end

### General promotion rules
convert{T}(::Type{Factorization{T}}, F::Factorization{T}) = F
inv{T}(F::Factorization{T}) = A_ldiv_B!(F, eye(T, size(F,1)))
function \{TF<:Number,TB<:Number,N}(F::Factorization{TF}, B::AbstractArray{TB,N})
    TFB = typeof(one(TF)/one(TB))
    A_ldiv_B!(convert(Factorization{TFB}, F), TB == TFB ? copy(B) : convert(AbstractArray{TFB,N}, B))
end

function Ac_ldiv_B{TF<:Number,TB<:Number,N}(F::Factorization{TF}, B::AbstractArray{TB,N})
    TFB = typeof(one(TF)/one(TB))
    Ac_ldiv_B!(convert(Factorization{TFB}, F), TB == TFB ? copy(B) : convert(AbstractArray{TFB,N}, B))
end

function At_ldiv_B{TF<:Number,TB<:Number,N}(F::Factorization{TF}, B::AbstractArray{TB,N})
    TFB = typeof(one(TF)/one(TB))
    At_ldiv_B!(convert(Factorization{TFB}, F), TB == TFB ? copy(B) : convert(AbstractArray{TFB,N}, B))
end

## reconstruct the original matrix
full(F::QR) = F[:Q] * F[:R]
full(F::QRCompactWY) = F[:Q] * F[:R]
full(F::QRPivoted) = (F[:Q] * F[:R])[:,invperm(F[:p])]

## Can we determine the source/result is Real?  This is not stored in the type Eigen
full(F::Eigen) = F.vectors * Diagonal(F.values) / F.vectors

full(F::Hessenberg) = (fq = full(F[:Q]); (fq * F[:H]) * fq')

full(F::Schur) = (F.Z * F.T) * F.Z'

full(F::SVD) = (F.U * Diagonal(F.S)) * F.Vt
