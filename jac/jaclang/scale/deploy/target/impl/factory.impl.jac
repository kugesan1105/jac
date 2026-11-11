impl ensure_deploy_tooling(dry_run: bool = False) {
    if dry_run {
        return;
    }
    missing = missing_capability_dists("deploy.k8s");
    if not missing {
        return;
    }

    console.print(
        f"Deploy tooling missing; installing {', '.join(missing)} "
        f"(capability 'deploy.k8s') into the jac global site."
    );
    if not ensure_global_capability("deploy.k8s") {
        console.warning(
            "Automatic install of the deploy tooling failed; run "
            "'jac install --scale' to see the full pip output."
        );
    }
}

impl require_deploy_tooling(dry_run: bool = False) {
    if dry_run {
        return;
    }
    require_optional("kubernetes", "deploy.k8s");
    shim = sys.modules.get("jaclang.scale._optdeps.kubernetes");
    if shim is not None and not shim.HAS_KUBERNETES {
        raise RuntimeError(
            "The Kubernetes client was installed after this process had already "
            "loaded without it. Restart the process (for a CLI command, run it again)."
        );
    }
}

impl check_deploy_target(target: str) -> None {
    if target not in DEPLOY_TARGETS {
        raise ValueError(
            f"Unsupported deployment target '{target}'. Supported targets: "
            f"{', '.join(DEPLOY_TARGETS)}."
        );
    }
}

impl create_kubernetes_target(
    target_type: str,
    config: dict[str, any],
    logger: (Logger | None) = None,
    dry_run: bool = False
) -> KubernetesTarget {
    check_deploy_target(target_type);
    ensure_deploy_tooling(dry_run);
    require_deploy_tooling(dry_run);
    import from jaclang.scale.deploy.target.kubernetes.kubernetes_config {
        KubernetesConfig
    }
    import from jaclang.scale.deploy.target.kubernetes.target { KubernetesTarget }
    k8s_config = KubernetesConfig.from_dict(KubernetesConfig, config);
    return KubernetesTarget(config=k8s_config, logger=logger, dry_run=dry_run);
}
