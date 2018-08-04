function initialize!(integrator, cache::ABDF2ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

@muladd function perform_step!(integrator, cache::ABDF2ConstantCache, repeat_step=false)
  @unpack t,f,p = integrator
  @unpack nlsolve,dtₙ₋₁ = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  alg = unwrap_alg(integrator, true)
  dtₙ, uₙ, uₙ₋₁, uₙ₋₂ = integrator.dt, integrator.u, integrator.uprev, integrator.uprev2

  if integrator.iter == 1 && !integrator.u_modified
    cache.dtₙ₋₁ = dtₙ
    perform_step!(integrator, cache.eulercache, repeat_step)
    cache.fsalfirstprev = integrator.fsalfirst
    return
  end

  # precalculations
  fₙ₋₁ = integrator.fsalfirst
  ρ = dtₙ/dtₙ₋₁
  d = 2//3
  ddt = d*dtₙ
  dtmp = 1//3*ρ^2
  d1 = 1+dtmp
  d2 = -dtmp
  d3 = -(ρ-1)*1//3

  # calculate W
  typeof(nlsolve!) <: NLNewton && ( nlcache.W = calc_W!(integrator, cache, ddt, repeat_step) )

  zₙ₋₁ = dtₙ*fₙ₋₁
  # initial guess
  if alg.extrapolant == :linear
    z = dtₙ*fₙ₋₁
  else # :constant
    z = zero(uₙ)
  end
  nlcache.z = z

  nlcache.tmp = d1*uₙ₋₁ + d2*uₙ₋₂ + d3*zₙ₋₁
  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return

  uₙ = nlcache.tmp + d*z
  integrator.fsallast = f(uₙ,p,t+dtₙ)

  if integrator.opts.adaptive
    tmp = integrator.fsallast - (1+dtₙ/dtₙ₋₁)*integrator.fsalfirst + (dtₙ/dtₙ₋₁)*cache.fsalfirstprev
    est = (dtₙ₋₁+dtₙ)/6 * tmp
    atmp = calculate_residuals(est, uₙ₋₁, uₙ, integrator.opts.abstol, integrator.opts.reltol,integrator.opts.internalnorm)
    integrator.EEst = integrator.opts.internalnorm(atmp)
  end

  ################################### Finalize

  cache.dtₙ₋₁ = dtₙ
  nlcache.ηold = η
  nlcache.nl_iters = iter
  if integrator.EEst < one(integrator.EEst)
    cache.fsalfirstprev = integrator.fsalfirst
  end

  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = uₙ
  return
end

function initialize!(integrator, cache::ABDF2Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
end

@muladd function perform_step!(integrator, cache::ABDF2Cache, repeat_step=false)
  @unpack t,dt,f,p = integrator
  @unpack z,k,b,J,W,tmp,atmp,dtₙ₋₁,zₙ₋₁,nlsolve = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  alg = unwrap_alg(integrator, true)
  uₙ,uₙ₋₁,uₙ₋₂,dtₙ = integrator.u,integrator.uprev,integrator.uprev2,integrator.dt

  if integrator.iter == 1 && !integrator.u_modified
    cache.dtₙ₋₁ = dtₙ
    perform_step!(integrator, cache.eulercache, repeat_step)
    cache.fsalfirstprev .= integrator.fsalfirst
    nlcache.tmp = tmp
    return
  end

  # precalculations
  fₙ₋₁ = integrator.fsalfirst
  ρ = dtₙ/dtₙ₋₁
  d = 2//3
  ddt = d*dtₙ
  dtmp = 1//3*ρ^2
  d1 = 1+dtmp
  d2 = -dtmp
  d3 = -(ρ-1)*1//3

  typeof(nlsolve) <: NLNewton && calc_W!(integrator, cache, ddt, repeat_step)

  @. zₙ₋₁ = dtₙ*fₙ₋₁
  # initial guess
  if alg.extrapolant == :linear
    @. z = dtₙ*fₙ₋₁
  else # :constant
    z .= zero(eltype(z))
  end

  @. tmp = d1*uₙ₋₁ + d2*uₙ₋₂ + d3*zₙ₋₁
  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return

  @. uₙ = tmp + d*z

  f(integrator.fsallast, uₙ, p, t+dtₙ)
  if integrator.opts.adaptive
    btilde0 = (dtₙ₋₁+dtₙ)*1//6
    btilde1 = 1+dtₙ/dtₙ₋₁
    btilde2 = dtₙ/dtₙ₋₁
    @. tmp = btilde0*(integrator.fsallast - btilde1*integrator.fsalfirst + btilde2*cache.fsalfirstprev)
    calculate_residuals!(atmp, tmp, uₙ₋₁, uₙ, integrator.opts.abstol, integrator.opts.reltol,integrator.opts.internalnorm)
    integrator.EEst = integrator.opts.internalnorm(atmp)
  end

  ################################### Finalize

  nlcache.ηold = η
  nlcache.nl_iters = iter
  cache.dtₙ₋₁ = dtₙ
  if integrator.EEst < one(integrator.EEst)
    @. cache.fsalfirstprev = integrator.fsalfirst
  end
  return
end

# SBDF2

function initialize!(integrator, cache::SBDF2ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::SBDF2ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack uprev2,k₁,k₂ = cache
  cnt = integrator.iter
  f1 = integrator.f.f1
  f2 = integrator.f.f2
  du₁ = f1(uprev,p,t)
  du₂ = integrator.fsalfirst - du₁
  if cnt == 1
    tmp = uprev + dt*du₂
  else
    tmp = (4*uprev - uprev2)/3 + (dt/3)*(4*du₂ - 2*k₂)
  end
  # Implicit part
  # precalculations
  γ = 1//1
  if cnt != 1
   γ = 2//3
  end
  γdt = γ*dt
  W = calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  zprev = dt*du₁
  z = zprev # Constant extrapolation

  nlcache = nlsolve_cache(alg, cache, z, tmp, W, γ, 1, true)
  z,η,iter,fail_convergence = diffeq_nlsolve!(integrator, nlcache, cache, alg.nonlinsolve)
  fail_convergence && return
  u = tmp + γ*z

  cache.uprev2 = uprev
  cache.k₁ = du₁
  cache.k₂ = du₂
  cache.ηold = η
  cache.newton_iters = iter
  integrator.fsallast = f1(u, p, t+dt) + f2(u, p, t+dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::SBDF2Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t)
end

function perform_step!(integrator, cache::SBDF2Cache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack tmp,uprev2,k,k₁,k₂,du₁,z = cache
  cnt = integrator.iter
  f1 = integrator.f.f1
  f2 = integrator.f.f2
  f1(du₁, uprev, p, t)
  # Explicit part
  if cnt == 1
    @. tmp = uprev + dt * (integrator.fsalfirst - du₁)
  else
    @. tmp = (4*uprev - uprev2)/3 + (dt/3)*(4*(integrator.fsalfirst - du₁) - 2*k₂)
  end
  # Implicit part
  # precalculations
  γ = 1//1
  if cnt != 1
   γ = 2//3
  end
  γdt = γ*dt
  new_W = calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  @. z = dt*du₁

  nlcache = nlsolve_cache(alg, cache, z, tmp, γ, 1, new_W)
  z,η,iter,fail_convergence = diffeq_nlsolve!(integrator, nlcache, cache, alg.nonlinsolve)
  fail_convergence && return
  @. u = tmp + γ*z

  cache.uprev2 .= uprev
  cache.k₁ .= du₁
  @. cache.k₂ = integrator.fsalfirst - du₁
  cache.ηold = η
  cache.newton_iters = iter
  integrator.f(k,u,p,t+dt)
end

# SBDF3

function initialize!(integrator, cache::SBDF3ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::SBDF3ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack uprev2,uprev3,k₁,k₂ = cache
  cnt = integrator.iter
  f1 = integrator.f.f1
  f2 = integrator.f.f2
  du₁ = f1(uprev,p,t)
  du₂ = integrator.fsalfirst - du₁
  if cnt == 1
    tmp = uprev + dt*du₂
  elseif cnt == 2
    tmp = (4*uprev - uprev2)/3 + (dt/3)*(4*du₂ - 2*k₁)
  else
    tmp = (6//11) * (3*uprev - 3//2*uprev2 + 1//3*uprev3 + dt*(3*(du₂ - k₁) + k₂))
  end
  # Implicit part
  # precalculations
  if cnt == 1
    γ = 1//1
  elseif cnt == 2
    γ = 2//3
  else
    γ = 6//11
  end
  γdt = γ*dt
  W = calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  zprev = dt*du₁
  z = zprev # Constant extrapolation

  nlcache = nlsolve_cache(alg, cache, z, tmp, W, γ, 1, true)
  z,η,iter,fail_convergence = diffeq_nlsolve!(integrator, nlcache, cache, alg.nonlinsolve)
  fail_convergence && return
  u = tmp + γ*z

  cache.uprev3 = uprev2
  cache.uprev2 = uprev
  cache.k₂ = k₁
  cache.k₁ = du₂
  cache.ηold = η
  cache.newton_iters = iter
  integrator.fsallast = f1(u, p, t+dt) + f2(u, p, t+dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::SBDF3Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t)
end

function perform_step!(integrator, cache::SBDF3Cache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack tmp,uprev2,uprev3,k,k₁,k₂,du₁,z = cache
  cnt = integrator.iter
  f1 = integrator.f.f1
  f2 = integrator.f.f2
  f1(du₁, uprev, p, t)
  # Explicit part
  if cnt == 1
    @. tmp = uprev + dt*(integrator.fsalfirst - du₁)
  elseif cnt == 2
    @. tmp = (4*uprev - uprev2)/3 + (dt/3)*(4*(integrator.fsalfirst - du₁) - 2*k₁)
  else
    @. tmp = (6//11) * (3*uprev - 3//2*uprev2 + 1//3*uprev3 + dt*(3*((integrator.fsalfirst - du₁) - k₁) + k₂))
  end
  # Implicit part
  # precalculations
  if cnt == 1
    γ = 1//1
  elseif cnt == 2
    γ = 2//3
  else
    γ = 6//11
  end
  γdt = γ*dt
  new_W = calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  @. z = dt*du₁

  nlcache = nlsolve_cache(alg, cache, z, tmp, γ, 1, new_W)
  z,η,iter,fail_convergence = diffeq_nlsolve!(integrator, nlcache, cache, alg.nonlinsolve)
  fail_convergence && return
  @. u = tmp + γ*z

  cache.uprev3 .= uprev2
  cache.uprev2 .= uprev
  cache.k₂ .= k₁
  @. cache.k₁ = integrator.fsalfirst - du₁
  cache.ηold = η
  cache.newton_iters = iter
  integrator.f(k,u,p,t+dt)
end

# SBDF4

function initialize!(integrator, cache::SBDF4ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::SBDF4ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack uprev2,uprev3,uprev4,k₁,k₂,k₃ = cache
  cnt = integrator.iter
  f1 = integrator.f.f1
  f2 = integrator.f.f2
  du₁ = f1(uprev,p,t)
  du₂ = integrator.fsalfirst - du₁
  if cnt == 1
    tmp = uprev + dt*du₂
  elseif cnt == 2
    tmp = (4*uprev - uprev2)/3 + (dt/3)*(4*du₂ - 2*k₁)
  elseif cnt == 3
    tmp = (6//11) * (3*uprev - 3//2*uprev2 + 1//3*uprev3 + dt*(3*(du₂ - k₁) + k₂))
  else
    tmp = (12//25) * (4*uprev - 3*uprev2 + 4//3*uprev3 - 1//4*uprev4 + dt*(4*du₂ - 6*k₁ + 4*k₂ - k₃))
  end
  # Implicit part
  # precalculations
  if cnt == 1
    γ = 1//1
  elseif cnt == 2
    γ = 2//3
  elseif cnt == 3
    γ = 6//11
  else
    γ = 12//25
  end
  γdt = γ*dt
  W = calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  zprev = dt*du₁
  z = zprev # Constant extrapolation

  nlcache = nlsolve_cache(alg, cache, z, tmp, W, γ, 1, true)
  z,η,iter,fail_convergence = diffeq_nlsolve!(integrator, nlcache, cache, alg.nonlinsolve)
  fail_convergence && return
  u = tmp + γ*z

  cache.uprev4 = uprev3
  cache.uprev3 = uprev2
  cache.uprev2 = uprev
  cache.k₃ = k₂
  cache.k₂ = k₁
  cache.k₁ = du₂
  cache.ηold = η
  cache.newton_iters = iter
  integrator.fsallast = f1(u, p, t+dt) + f2(u, p, t+dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::SBDF4Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t)
end

function perform_step!(integrator, cache::SBDF4Cache, repeat_step=false)
  @unpack t,dt,uprev,u,f,p,alg = integrator
  @unpack tmp,uprev2,uprev3,uprev4,k,k₁,k₂,k₃,du₁,z = cache
  cnt = integrator.iter
  f1 = integrator.f.f1
  f2 = integrator.f.f2
  f1(du₁, uprev, p, t)
  # Explicit part
  if cnt == 1
    @. tmp = uprev + dt*(integrator.fsalfirst - du₁)
  elseif cnt == 2
    @. tmp = (4*uprev - uprev2)/3 + (dt/3)*(4*(integrator.fsalfirst - du₁) - 2*k₁)
  elseif cnt == 3
    @. tmp = (6//11) * (3*uprev - 3//2*uprev2 + 1//3*uprev3 + dt*(3*((integrator.fsalfirst - du₁) - k₁) + k₂))
  else
    @. tmp = (12//25) * (4*uprev - 3*uprev2 + 4//3*uprev3 - 1//4*uprev4 + dt*(4*(integrator.fsalfirst - du₁) - 6*k₁ + 4*k₂ - k₃))
  end
  # Implicit part
  # precalculations
  if cnt == 1
    γ = 1//1
  elseif cnt == 2
    γ = 2//3
  elseif cnt == 3
    γ = 6//11
  else
    γ = 12//25
  end
  γdt = γ*dt
  new_W = calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  @. z = dt*du₁

  nlcache = nlsolve_cache(alg, cache, z, tmp, γ, 1, new_W)
  z,η,iter,fail_convergence = diffeq_nlsolve!(integrator, nlcache, cache, alg.nonlinsolve)
  fail_convergence && return
  @. u = tmp + γ*z

  cache.uprev4 .= uprev3
  cache.uprev3 .= uprev2
  cache.uprev2 .= uprev
  cache.k₃ .= k₂
  cache.k₂ .= k₁
  @. cache.k₁ = integrator.fsalfirst - du₁
  cache.ηold = η
  cache.newton_iters = iter
  integrator.f(k,u,p,t+dt)
end

# QNDF1

function initialize!(integrator, cache::QNDF1ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::QNDF1ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,D,D2,R,U,dtₙ₋₁,nlsolve = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  alg = unwrap_alg(integrator, true)
  cnt = integrator.iter
  k = 1
  if cnt == 1
    κ = zero(alg.kappa)
  else
    κ = alg.kappa
    ρ = dt/dtₙ₋₁
    D[1] = uprev - uprev2   # backward diff
    if ρ != 1
      R!(k,ρ,cache)
      D[1] = D[1] * (R[1] * U[1])
    end
  end

  # precalculations
  γ₁ = 1//1
  γ = inv((1-κ)*γ₁)

  u₀ = uprev + D[1]
  ϕ = γ * (γ₁*D[1])
  nlcache.tmp = u₀ - ϕ

  γdt = γ*dt
  typeof(nlsolve!) <: NLNewton && ( nlcache.W = calc_W!(integrator, cache, γdt, repeat_step) )

  # initial guess
  nlcache.z = dt*integrator.fsalfirst
  nlcache.γ = γ

  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return
  u = nlcache.tmp + γ*z

  if integrator.opts.adaptive && integrator.success_iter > 0
    D2[1] = u - uprev
    D2[2] = D2[1] - D[1]
    utilde = (κ*γ₁ + inv(k+1)) * D2[2]
    atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
    integrator.EEst = integrator.opts.internalnorm(atmp)
    if integrator.EEst > one(integrator.EEst)
      return
    end
  else
    integrator.EEst = one(integrator.EEst)
  end
  cache.dtₙ₋₁ = dt
  cache.uprev2 = uprev
  nlcache.ηold = η
  nlcache.nl_iters = iter
  integrator.fsallast = f(u, p, t+dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::QNDF1Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
end

function perform_step!(integrator,cache::QNDF1Cache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,D,D2,R,U,dtₙ₋₁,tmp,z,W,utilde,atmp,nlsolve = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  alg = unwrap_alg(integrator, true)
  cnt = integrator.iter
  k = 1
  if cnt == 1
    κ = zero(alg.kappa)
  else
    κ = alg.kappa
    ρ = dt/dtₙ₋₁
    @. D[1] = uprev - uprev2 # backward diff
    if ρ != 1
      R!(k,ρ,cache)
      @. D[1] = D[1] * (R[1] * U[1])
    end
  end

  # precalculations
  γ₁ = 1//1
  nlcache.γ = γ = inv((1-κ)*γ₁)
  @. tmp = uprev + D[1] - γ * (γ₁*D[1])

  γdt = γ*dt
  typeof(nlsolve) <: NLNewton && calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  @. z = dt*integrator.fsalfirst

  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return
  @. u = tmp + γ*z

  if integrator.opts.adaptive && integrator.success_iter > 0
    @. D2[1] = u - uprev
    @. D2[2] = D2[1] - D[1]
    @. utilde = (κ*γ₁ + inv(k+1)) * D2[2]
    calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
    integrator.EEst = integrator.opts.internalnorm(atmp)
    if integrator.EEst > one(integrator.EEst)
      return
    end
  else
    integrator.EEst = one(integrator.EEst)
  end
  cache.dtₙ₋₁ = dt
  cache.uprev2 .= uprev
  nlcache.ηold = η
  nlcache.nl_iters = iter
  f(integrator.fsallast, u, p, t+dt)
end

function initialize!(integrator, cache::QNDF2ConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::QNDF2ConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,uprev3,dtₙ₋₁,dtₙ₋₂,D,D2,R,U,nlsolve = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  alg = unwrap_alg(integrator, true)
  cnt = integrator.iter
  k = 2
  if cnt == 1 || cnt == 2
    κ = zero(alg.kappa)
    γ₁ = 1//1
    γ₂ = 1//1
  elseif dtₙ₋₁ != dtₙ₋₂
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ₁ = dt/dtₙ₋₁
    ρ₂ = dt/dtₙ₋₂
    D[1] = uprev - uprev2
    D[1] = D[1] * ρ₁
    D[2] = D[1] - ((uprev2 - uprev3) * ρ₂)
  else
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ = dt/dtₙ₋₁
    # backward diff
    D[1] = uprev - uprev2
    D[2] = D[1] - (uprev2 - uprev3)
    if ρ != 1
      R!(k,ρ,cache)
      R .= R * U
      D[1] = D[1] * R[1,1] + D[2] * R[2,1]
      D[2] = D[1] * R[1,2] + D[2] * R[2,2]
    end
  end

  # precalculations
  nlcache.γ = γ = inv((1-κ)*γ₂)
  u₀ = uprev + D[1] + D[2]
  ϕ = γ * (γ₁*D[1] + γ₂*D[2])
  nlcache.tmp = u₀ - ϕ

  γdt = γ*dt
  typeof(nlsolve!) <: NLNewton && ( nlcache.W = calc_W!(integrator, cache, γdt, repeat_step) )

  # initial guess
  nlcache.z = dt*integrator.fsalfirst

  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return
  u = nlcache.tmp + γ*z

  if integrator.opts.adaptive
    if integrator.success_iter == 0
      integrator.EEst = one(integrator.EEst)
    elseif integrator.success_iter == 1
      utilde = (u - uprev) - ((uprev - uprev2) * dt/dtₙ₋₁)
      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    else
      D2[1] = u - uprev
      D2[2] = D2[1] - D[1]
      D2[3] = D2[2] - D[2]
      utilde = (κ*γ₂ + inv(k+1)) * D2[3]
      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    end
  end
  if integrator.EEst > one(integrator.EEst)
    return
  end

  cache.uprev3 = uprev2
  cache.uprev2 = uprev
  cache.dtₙ₋₂ = dtₙ₋₁
  cache.dtₙ₋₁ = dt
  nlcache.ηold = η
  nlcache.nl_iters = iter
  integrator.fsallast = f(u, p, t+dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
  return
end

function initialize!(integrator, cache::QNDF2Cache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
end

function perform_step!(integrator,cache::QNDF2Cache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack uprev2,uprev3,dtₙ₋₁,dtₙ₋₂,D,D2,R,U,tmp,utilde,atmp,W,z,nlsolve = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  alg = unwrap_alg(integrator, true)
  cnt = integrator.iter
  k = 2
  if cnt == 1 || cnt == 2
    κ = zero(alg.kappa)
    γ₁ = 1//1
    γ₂ = 1//1
  elseif dtₙ₋₁ != dtₙ₋₂
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ₁ = dt/dtₙ₋₁
    ρ₂ = dt/dtₙ₋₂
    @. D[1] = uprev - uprev2
    @. D[1] = D[1] * ρ₁
    @. D[2] = D[1] - ((uprev2 - uprev3) * ρ₂)
  else
    κ = alg.kappa
    γ₁ = 1//1
    γ₂ = 1//1 + 1//2
    ρ = dt/dtₙ₋₁
    # backward diff
    @. D[1] = uprev - uprev2
    @. D[2] = D[1] - (uprev2 - uprev3)
    if ρ != 1
      R!(k,ρ,cache)
      R .= R * U
      @. D[1] = D[1] * R[1,1] + D[2] * R[2,1]
      @. D[2] = D[1] * R[1,2] + D[2] * R[2,2]
    end
  end

  # precalculations
  nlcache.γ = γ = inv((1-κ)*γ₂)
  @. tmp = uprev + D[1] + D[2] - γ * (γ₁*D[1] + γ₂*D[2])

  γdt = γ*dt
  typeof(nlsolve) <: NLNewton && calc_W!(integrator, cache, γdt, repeat_step)

  # initial guess
  @. z = dt*integrator.fsalfirst

  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return
  @. u = tmp + γ*z

  if integrator.opts.adaptive
    if integrator.success_iter == 0
      integrator.EEst = one(integrator.EEst)
    elseif integrator.success_iter == 1
      @. utilde = (u - uprev) - ((uprev - uprev2) * dt/dtₙ₋₁)
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    else
      @. D2[1] = u - uprev
      @. D2[2] = D2[1] - D[1]
      @. D2[3] = D2[2] - D[2]
      @. utilde = (κ*γ₂ + inv(k+1)) * D2[3]
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    end
  end
  if integrator.EEst > one(integrator.EEst)
    return
  end

  cache.uprev3 .= uprev2
  cache.uprev2 .= uprev
  cache.dtₙ₋₂ = dtₙ₋₁
  cache.dtₙ₋₁ = dt
  nlcache.ηold = η
  nlcache.nl_iters = iter
  f(integrator.fsallast, u, p, t+dt)
  return
end

function initialize!(integrator, cache::QNDFConstantCache)
  integrator.kshortsize = 2
  integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)
  integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal

  # Avoid undefined entries if k is an array of arrays
  integrator.fsallast = zero(integrator.fsalfirst)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
end

function perform_step!(integrator,cache::QNDFConstantCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack udiff,dts,order,max_order,D,D2,R,U,nlsolve = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  k = order
  cnt = integrator.iter
  κ = integrator.alg.kappa[k]
  γ = inv((1-κ)*γₖ[k])
  flag = true
  for i in 2:k
    if dts[i] != dts[1]
      flag = false
      break
    end
  end
  if cnt > 2
    if flag
      ρ = dt/dts[1]
      # backward diff
      n = k+1
      if cnt == 3
        n = k
      end
      for i = 1:n
        D2[1,i] = udiff[i]
      end
      backward_diff!(cache,D,D2,k)
      if ρ != 1
        U!(k,U)
        R!(k,ρ,cache)
        R .= R * U
        reinterpolate_history!(cache,D,R,k)
      end
    else
      n = k+1
      if cnt == 3
        n = k
      end
      for i = 1:n
        D2[1,i] = udiff[i] * dt/dts[i]
      end
      backward_diff!(cache,D,D2,k)
    end
  else
    γ = 1//1
  end
  nlcache.γ = γ
  # precalculations
  u₀ = uprev + sum(D)  # u₀ is predicted value
  ϕ = zero(γ)
  for i = 1:k
    ϕ += γₖ[i]*D[i]
  end
  ϕ *= γ
  nlcache.tmp = u₀ - ϕ
  γdt = γ*dt
  typeof(nlsolve!) <: NLNewton && ( nlcache.W = calc_W!(integrator, cache, γdt, repeat_step) )
  # initial guess
  nlcache.z = dt*integrator.fsalfirst

  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return
  u = nlcache.tmp + γ*z

  if integrator.opts.adaptive
    if cnt == 1
      integrator.EEst = one(integrator.EEst)
    elseif cnt == 2
      utilde = (u - uprev) - (udiff[1] * dt/dts[1])
      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    else
      δ = u - uprev
      for i = 1:k
        δ -= D[i]
      end
      utilde = (κ*γₖ[k] + inv(k+1)) * δ
      atmp = calculate_residuals(utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    end
    
    if cnt == 1
      cache.order = 1
    elseif cnt <= 3
      cache.order = 2
    else
      errm1 = 0
      if k > 1
        utildem1 = (κ*γₖ[k-1] + inv(k)) * D[k]
        atmpm1 = calculate_residuals(utildem1, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
        errm1 = integrator.opts.internalnorm(atmpm1)
      end
      backward_diff!(cache,D,D2,k+1,false)
      δ = u - uprev
      for i = 1:(k+1)
        δ -= D2[i,1]
      end
      utildep1 = (κ*γₖ[k+1] + inv(k+2)) * δ
      atmpp1 = calculate_residuals(utildep1, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      errp1 = integrator.opts.internalnorm(atmpp1)
      pass = stepsize_and_order!(cache, integrator.EEst, errm1, errp1, dt, k)
      if pass == false
        cache.c = cache.c + 1
        fill!(D, zero(u)); fill!(D2, zero(u))
        fill!(R, zero(t)); fill!(U, zero(t))
        return
      end
      cache.c = 0
    end # cnt == 1
  end # integrator.opts.adaptive
  for i = 6:-1:2
    dts[i] = dts[i-1]
    udiff[i] = udiff[i-1]
  end
  dts[1] = dt
  udiff[1] = u - uprev
  fill!(D, zero(u)); fill!(D2, zero(u))
  fill!(R, zero(t)); fill!(U, zero(t))

  nlcache.ηold = η
  nlcache.nl_iters = iter
  integrator.fsallast = f(u, p, t+dt)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.u = u
end

function initialize!(integrator, cache::QNDFCache)
  integrator.kshortsize = 2
  integrator.fsalfirst = cache.fsalfirst
  integrator.fsallast = cache.k
  resize!(integrator.k, integrator.kshortsize)
  integrator.k[1] = integrator.fsalfirst
  integrator.k[2] = integrator.fsallast
  integrator.f(integrator.fsalfirst, integrator.uprev, integrator.p, integrator.t) # For the interpolation, needs k at the updated point
end

function perform_step!(integrator,cache::QNDFCache,repeat_step=false)
  @unpack t,dt,uprev,u,f,p = integrator
  @unpack udiff,dts,order,max_order,D,D2,R,U,tmp,utilde,atmp,W,z,nlsolve = cache
  nlsolve!, nlcache = nlsolve, nlsolve.cache
  cnt = integrator.iter
  k = order
  κ = integrator.alg.kappa[k]
  γ = inv((1-κ)*γₖ[k])
  flag = true
  for i in 2:k
    if dts[i] != dts[1]
      flag = false
      break
    end
  end
  if cnt > 2
    if flag
      ρ = dt/dts[1]
      # backward diff
      n = k+1
      if cnt == 3
        n = k
      end
      for i = 1:n
        D2[1,i] .= udiff[i]
      end
      backward_diff!(cache,D,D2,k)
      if ρ != 1
        U!(k,U)
        R!(k,ρ,cache)
        R .= R * U
        reinterpolate_history!(cache,D,R,k)
      end
    else
      n = k+1
      if cnt == 3
        n = k
      end
      for i = 1:n
        @. D2[1,i] = udiff[i] * dt/dts[i]
      end
      backward_diff!(cache,D,D2,k)
    end
  else
    γ = 1//1
  end
  nlcache.γ = γ
  # precalculations
  ϕ = zero(u)
  for i = 1:k
    @. ϕ += γₖ[i]*D[i]
  end
  @. ϕ *= γ
  tm = zero(u)
  for i = 1:k
    @. tm += D[i]
  end
  @. tmp = uprev + tm - ϕ

  γdt = γ*dt
  typeof(nlsolve) <: NLNewton && calc_W!(integrator, cache, γdt, repeat_step)
  # initial guess
  @. z = dt*integrator.fsalfirst

  z,η,iter,fail_convergence = nlsolve!(integrator)
  fail_convergence && return
  @. u = tmp + γ*z


  if integrator.opts.adaptive
    if cnt == 1
      integrator.EEst = one(integrator.EEst)
    elseif cnt == 2
      @. utilde = (u - uprev) - (udiff[1] * dt/dts[1])
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    else
      @. tmp = u - uprev
      for i = 1:k
        @. tmp -= D[i]
      end
      @. utilde = (κ*γₖ[k] + inv(k+1)) * tmp
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      integrator.EEst = integrator.opts.internalnorm(atmp)
    end

    if cnt == 1
      cache.order = 1
    elseif cnt <= 3
      cache.order = 2
    else
      errm1 = 0
      if k > 1
        @. utilde = (κ*γₖ[k-1] + inv(k)) * D[k]
        calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
        errm1 = integrator.opts.internalnorm(atmp)
      end
      backward_diff!(cache,D,D2,k+1,false)
      @. tmp = u - uprev
      for i = 1:(k+1)
        @. tmp -= D2[i,1]
      end
      @. utilde = (κ*γₖ[k+1] + inv(k+2)) * tmp
      calculate_residuals!(atmp, utilde, uprev, u, integrator.opts.abstol, integrator.opts.reltol, integrator.opts.internalnorm)
      errp1 = integrator.opts.internalnorm(atmp)
      pass = stepsize_and_order!(cache, integrator.EEst, errm1, errp1, dt, k)
      if pass == false
        for i = 1:5
          D[i] = zero(u)
        end
        for i = 1:6
          for j = 1:6
            D2[i,j] = zero(u)
          end
        end
        fill!(R, zero(t)); fill!(U, zero(t))
        cache.c = cache.c + 1
        return
      end
      cache.c = 0
    end # cnt == 1
  end # integrator.opts.adaptive
  for i = 6:-1:2
    dts[i] = dts[i-1]
    udiff[i] .= udiff[i-1]
  end
  dts[1] = dt
  @. udiff[1] = u - uprev
  for i = 1:5
    D[i] = zero(u)
  end
  for i = 1:6
    for j = 1:6
      D2[i,j] = zero(u)
    end
  end
  fill!(R, zero(t)); fill!(U, zero(t))

  nlcache.ηold = η
  nlcache.nl_iters = iter
  f(integrator.fsallast, u, p, t+dt)
end
