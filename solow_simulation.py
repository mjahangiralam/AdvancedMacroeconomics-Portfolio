# This is a Solow Model Simulation
import numpy as np
import matplotlib.pyplot as plt


def simulate_solow_saving_shock(
    T: int = 81,
    A: float = 1.0,
    alpha: float = 0.333,
    s0: float = 0.30,
    s1: float = 0.303,   # 1% increase relative to 0.30
    n: float = 0.01,
    g: float = 0.02,
    delta: float = 0.03,
):
    """
    Simulate a discrete-time Solow model after a permanent saving-rate shock.

    Variables are per efficiency unit of labor unless otherwise noted.
    We assume a Cobb-Douglas production function:
        y_t = A * k_t^alpha

    Capital accumulation:
        k_{t+1} = [s_t * A * k_t^alpha + (1-delta) * k_t] / [(1+n)(1+g)]

    Real wage per efficiency unit:
        w_t = (1-alpha) * A * k_t^alpha

    Real interest rate (net of depreciation, matching common macro convention):
        r_t = alpha * A * k_t^(alpha - 1) - delta
    """

    # Time
    t = np.arange(T)

    # Permanent saving shock from period 1 onward
    s_path = np.full(T, s0)
    s_path[1:] = s1

    # Initial steady state under s0
    # From discrete-time steady state:
    # k* = [sA / ((1+n)(1+g) - (1-delta))]^(1/(1-alpha))
    denom = (1 + n) * (1 + g) - (1 - delta)
    if denom <= 0:
        raise ValueError("Invalid parameters: steady-state denominator must be positive.")

    k_ss0 = (s0 * A / denom) ** (1.0 / (1.0 - alpha))

    # Storage
    k = np.empty(T)
    y = np.empty(T)
    c = np.empty(T)
    w = np.empty(T)
    r = np.empty(T)

    # Start at initial balanced-growth-path steady state
    k[0] = k_ss0

    # Simulate
    for i in range(T):
        y[i] = A * k[i] ** alpha
        c[i] = (1.0 - s_path[i]) * y[i]
        w[i] = (1.0 - alpha) * y[i]
        r[i] = alpha * A * k[i] ** (alpha - 1.0) - delta

        if i < T - 1:
            k[i + 1] = (
                s_path[i] * y[i] + (1.0 - delta) * k[i]
            ) / ((1.0 + n) * (1.0 + g))

    return t, k, y, c, r, w, s_path


def make_figure():
    t, k, y, c, r, w, s_path = simulate_solow_saving_shock()

    fig, axes = plt.subplots(3, 2, figsize=(10, 7))
    axes = axes.ravel()

    series = [
        (k, "Capital"),
        (y, "Output"),
        (c, "Consumption"),
        (r, "Real Interest Rate"),
        (w, "Real Wage"),
        (s_path, "Savings Rate"),
    ]

    for ax, (data, title) in zip(axes, series):
        ax.plot(t, data, linewidth=2)
        ax.set_title(title, fontsize=11)
        ax.set_xlim(0, 80)
        ax.tick_params(direction="in", length=3, width=1)

    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    make_figure()
