"""Fixture: @asynccontextmanager method used in an `async with` statement.

Expected: 0 errors. The ability must be typed as an async context manager so the
`async with` __aenter__/__aexit__ check passes.
"""

import from contextlib { asynccontextmanager }

obj AsyncLock {
    @asynccontextmanager
    async def acquire -> None;
}

impl AsyncLock.acquire -> None {
    yield ;
}

async def use_async {
    lock = AsyncLock();
    async with lock.acquire() {
        print("inside");
    }
}
