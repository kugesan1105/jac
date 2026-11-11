import sys;

glob DEPLOY_TARGETS: tuple[str, ...] = ("kubernetes", "kubernetes-microservice");

def ensure_deploy_tooling(dry_run: bool = False);

def require_deploy_tooling(dry_run: bool = False);

def check_deploy_target(target: str) -> None;

def create_kubernetes_target(
    target_type: str,
    config: dict[str, any],
    logger: (Logger | None) = None,
    dry_run: bool = False
) -> KubernetesTarget;
