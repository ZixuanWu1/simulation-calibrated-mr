library(mvtnorm)


##' Generate (Y, X, F_ind) such that each family has exactly two individuals
##' 
##' @param sigma_esp: standard deviation of noise epsilon
##' @param eps_cor: correlation of noise within a family
##' @param sigma_x: standard deviation of X
##' @param sigma_f: standard deviation of f
##' @param rho: correlation between X and f
##' @param beta: true linear model coefficient
##' @param K: number of families
##' 
generate_data <- function(sigma_eps = .5, eps_cor = .1, sigma_x =1, 
                          sigma_f = 1, rho = .3, beta = 1, K = 1000, seed = 123){
  set.seed(seed)
  # Compute the covariance matrix for (X_{k1}, X_{k2}, f_k)
  Sigma = rbind(c(sigma_x^2, 0,  rho * sigma_x * sigma_f), 
                c(0, sigma_x^2,  rho * sigma_x * sigma_f), 
                c(sigma_x * sigma_f * rho,  sigma_x * sigma_f * rho, sigma_f^2))
  
  # Generate X, f
  x1_x2_f = rmvnorm(K, sigma = Sigma)
  x_1 = x1_x2_f[, 1]
  x_2 = x1_x2_f[, 2]
  f = x1_x2_f[, 3]
  
  # Generate noise
  noise = rmvnorm(K, sigma = rbind( c(sigma_eps^2, sigma_eps^2 * eps_cor), c(sigma_eps^2 * eps_cor, sigma_eps^2) ))
  
  # Generate Y
  y_1 = beta * x_1 + f + noise[, 1]
  y_2 = beta * x_2 + f + noise[, 2]
  Y = c(y_1, y_2)
  X = c(x_1, x_2)
  
  F_ind = c(1:K, 1:K)
  
  return(list(Y = Y, X = X, F_ind = F_ind))
  
}

##' Compute the calibrated estimator
##' @param Y: a vector contains response variable values
##' @param X: a vector contains transmitted allele values
##' @param F_ind: family index (from 1 to K)
##' @param alpha_ext: estimate of alpha from external data
##' @param alpha_ext_var: variance of alpha from external data
##' 
calibrated_estimator <- function(Y, X, F_ind, alpha_ext, alpha_ext_var){
  
  # Number of families
  K = max(F_ind)
  # Number of individuals
  N = length(X)
  
  # Compute family size for each individual
  size_dic = rep(0, K)
  F_size = rep(0, N)
  for(i in 1:N){
    size_dic[F_ind[i]] = size_dic[F_ind[i]]  + 1
  }
  
  for(i in 1:N){
    F_size[i] = size_dic[F_ind[i]]
  }
  
  # Compute the variance and mean of X
  mu_x = mean(X)
  sigma_x = sqrt(var(X))
  
  
  # Compute the correct model for internal data
  Y_tilde = Y
  X_tilde = X
  for(i in 1:K){
    Y_tilde[ F_ind == i ] = Y_tilde[ F_ind == i ]  - mean(Y_tilde[ F_ind == i ] )
    X_tilde[ F_ind == i ] = X_tilde[ F_ind == i ]  - mean(X_tilde[ F_ind == i ] )
  }
  
  correct_int = lm(Y_tilde ~ -1 +  X_tilde)
  beta_int = summary(correct_int)$coefficients[1]
  beta_int_sd = summary(correct_int)$coefficients[2]
  
  # Compute the incorrect model for internal data
  
  alpha_int = lm(Y ~  X)$coefficients[2]
  
  # Compute the C_{22}, C_{33}, C_{23}
  
  M = max(F_size)
  
  correct_var = rep( 0 , M)
  incorrect_var = rep( 0, M)
  correct_incorrect_cov = rep( 0, M)
  
  # Consider each family size separately
  for(m in 2:M){
    
    # Only look at family of size m
    X_sub = X[F_size == m]
    resid_sub = Y[F_size == m] - alpha_int * X_sub
    
    X_tilde_sub = X_tilde[F_size == m]
    resid_tilde_sub = Y_tilde[F_size == m] - beta_int * X_tilde_sub
    
    prod = resid_sub * X_sub
    prod_tilde = resid_tilde_sub * X_tilde_sub
    
    # This is for C22
    correct_var[m] = var(tapply(prod_tilde, F_ind[F_size == m], sum))
    # This is for C33
    incorrect_var[m] = var(tapply(prod, F_ind[F_size == m], sum))
    # This is for C23
    correct_incorrect_cov[m] = cov(tapply(prod, F_ind[F_size == m], sum), tapply(prod_tilde, F_ind[F_size == m], sum) )
  }  
  
  C22 = 0
  C33 = 0
  C23 = 0
  for(i in 1:K){
    C22 = C22 + correct_var[F_size[i]]
    C33 = C33 + incorrect_var[F_size[i]]
    C23 = C23 + correct_incorrect_cov[F_size[i]]
  }
  
  C22_const =  N / ( (N - K)^2 * sigma_x^4 )
  C33_const = 1 / (N * (sigma_x^2 + mu_x^2)^2)
  
  C22 = C22 * C22_const
  C33 = C33 * C33_const
  C23 = C23 * sqrt(C22_const * C33_const)
  
  # Compute the final calibrated estimator
  beta_cal = beta_int + C23 / ( N * alpha_ext_var + C33) * (alpha_ext - alpha_int)
  beta_cal_var = (C22 - C23^2 / (N * alpha_ext_var + C33) ) / N
  return(list(beta_cal  = beta_cal, beta_cal_sd = sqrt(beta_cal_var), beta_int = beta_int))
}



# Example
n_trial = 1000
K_ext = 50000
K_int = 200

beta_int = rep(0, n_trial)
beta_cal = rep(0, n_trial)

beta_cal_sd = rep(0, n_trial)
sigma_f = 1
for(i in 1:n_trial){
  external_data = generate_data(K = K_ext, sigma_f = sigma_f, seed = i, eps_cor = 0)
  model = summary(lm(external_data$Y[1:K_ext] ~  external_data$X[1:K_ext]))
  
  ext_estimate = model$coefficients[2, 1]
  ext_var = model$coefficients[2, 2]^2
  internal_data =  generate_data(K = K_int, sigma_f = sigma_f, seed = n_trial+ i, eps_cor = 0)
  result = calibrated_estimator(internal_data$Y, internal_data$X, internal_data$F_ind, ext_estimate
                                , ext_var)
  beta_int[i] = result$beta_int
  beta_cal[i] = result$beta_cal
  beta_cal_sd[i] = result$beta_cal_sd
}

# MSE

sum( (beta_int - 1)^2)
sum( (beta_cal - 1)^2)

# Variance reduction
var(beta_int)
var(beta_cal)

1 - var(beta_cal)/var(beta_int)

# Computed sd vs true sd

sd(beta_cal)
mean(beta_cal_sd)

# Density plot
plot(density(beta_int), ylim = c(0,20))
lines(density(beta_cal), col = "red")
