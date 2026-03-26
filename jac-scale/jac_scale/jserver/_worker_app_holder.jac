"""App factory for uvicorn multi-worker mode.

Each uvicorn worker process calls create_app() to create its own
FastAPI app instance. Module name and base path passed via env vars.
"""

import os;
import from fastapi { FastAPI }

"""Factory function called by each uvicorn worker to create the app."""
def create_app -> FastAPI {
    module_name = os.environ.get("JAC_WORKER_MODULE", "__main__");
    base_path = os.environ.get("JAC_WORKER_BASE_PATH", os.getcwd());

    # Import and load the jac module
    import from jaclang.jac0core.runtime { JacRuntime as Jac }
    Jac.jac_import(target=module_name, base_path=base_path, override_name="__main__");

    # Create the server
    import from jac_scale.serve { JacAPIServer }
    server = JacAPIServer(module_name=module_name, base_path=base_path);
    return server.server.create_server();
}
