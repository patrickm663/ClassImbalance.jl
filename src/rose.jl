import Distributions
import LinearAlgebra
import Statistics
import StatsBase
import DataFrames

ncol(df::DataFrames.AbstractDataFrame) = size(df, 2)

ncol(m::AbstractMatrix) = size(m, 2)

function numeric_columns(
        dat,
        )
    p = ncol(dat)
    is_numeric = falses(p)
    for j = 1:p
        typ = eltype(dat[:, j])
        if typ <: Real && typ ≠ Bool
            is_numeric[j] = true
        end
    end
    res = findall(is_numeric)
    res
end


function fill_diagonal!(
        X,
        diag_elems,
        )
    p = size(X, 2)
    for i = 1:p
        X[i, i] = diag_elems[i]
    end
end


function rose_real(
        X,
        n,
        ids_class,
        ids_generation,
        h_mult = 1,
        )
    X_array = convert(Array, X)
    p = size(X_array, 2)
    n_new = length(ids_generation)
    cons_kernel = (4/((p+2) * n))^(1/(p+4))

    if p ≠ 1
        # sd_mat = eye(p)
        sd_mat = Matrix(1.0LinearAlgebra.I, p, p)
        sd_vect = Statistics.std(X_array[ids_class, :];dims = 2,)
        fill_diagonal!(sd_mat, sd_vect)
        H = h_mult * cons_kernel * sd_mat
    else
        H = h_mult * cons_kernel * Statistics.std(X_array[ids_class, :])
    end
    X_new_num = randn(n_new, p) * H
    X_new_num = X_new_num + X_array[ids_generation, :]
    return X_new_num
end


function rose_sampling(
        X,
        y,
        prop,
        indcs_maj,
        indcs_min,
        y_majority,
        y_minority,
        h_mult_maj,
        h_mult_min,
        )
    n = size(X, 1)
    n_minority = sum(rand(Distributions.Binomial(1, prop), n))
    n_majority = n - n_minority

    indcs_maj_new = StatsBase.sample(indcs_maj, n_majority, replace = true)
    indcs_min_new = StatsBase.sample(indcs_min, n_minority, replace = true)

    numeric_cols = numeric_columns(X)

    # Create  X
    indcs = vcat(indcs_maj_new, indcs_min_new)
    X_new = X[indcs, :]
    if length(numeric_cols) > 0
        majority_rose_real_results = rose_real(
            X[:, numeric_cols],
            length(indcs_maj),
            indcs_maj,
            indcs_maj_new,
            h_mult_maj,
            )
        for k = 1:length(numeric_cols)
            col = numeric_cols[k]
            X_new[1:n_majority, col] = majority_rose_real_results[:, k]
        end
        minority_rose_real_results = rose_real(
            X[:, numeric_cols],
            length(indcs_min),
            indcs_min,
            indcs_min_new,
            h_mult_min,
            )
        for k = 1:length(numeric_cols)
            col = numeric_cols[k]
            X_new[(n_majority + 1):n, col] = minority_rose_real_results[:, k]
        end
    end

    # Create y
    y_new = similar(y)
    y_new[1:n_majority] .= y_majority
    y_new[(n_majority + 1):n] .= y_minority

    result = (X_new, y_new,)
    return result
end

"""
    classlabel(y)
Given a column from a DataFrames.DataFrame, this function returns the majority/minority class label.
"""
function classlabel(
        y::Array{T, 1},
        labeltype = :minority,
        ) where T
    count_dict = StatsBase.countmap(y)
    labels = collect(keys(count_dict))
    counts = collect(values(count_dict))
    if length(labels) > 2
        error("There are more than two classes in the target variable.")
    elseif length(labels) < 2
        error("There is only one class in the target variable.")
    end
    func = (labeltype == :majority) ? :argmax : :argmin
    indx = eval(func)(counts)
    res = collect(labels)[indx]
    res
end

function rose(
        dat::DataFrames.DataFrame,
        y_column::Symbol,
        prop::Float64 = 0.5,
        h_mult_maj = 1,
        h_mult_min = 1,
        )
    majority_label = classlabel(dat[y_column], :majority)
    minority_label = classlabel(dat[y_column], :minority)

    indcs_maj = findall(dat[y_column] .== majority_label)
    indcs_min = findall(dat[y_column] .== minority_label)
    p = size(dat, 2)
    y_indx = findfirst(names(dat) .== y_column)
    X_indcs = setdiff(1:p, y_indx)
    X = dat[:, X_indcs]
    y = dat[y_column]
    y_majority = majority_label
    y_minority = minority_label
    X_new, y_new = rose_sampling(
        X,
        y,
        prop,
        indcs_maj,
        indcs_min,
        y_majority,
        y_minority,
        h_mult_maj,
        h_mult_min,
        )
    result = X_new
    result[y_column] = y_new
    return result
end
