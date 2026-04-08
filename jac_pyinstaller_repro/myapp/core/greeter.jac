"""Greeter — imports across the package to exercise the module graph."""

import from myapp.utils.helpers { shout }

def greet(name: str) -> str {
    return shout(f"Hello, {name}");
}
