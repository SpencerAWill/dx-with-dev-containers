import { createRootRoute, Link, Outlet } from "@tanstack/react-router";

export const Route = createRootRoute({
  component: RootLayout,
});

function RootLayout() {
  return (
    <div className="app">
      <header className="header">
        <h1>
          <Link to="/">SnapSort</Link>
        </h1>
        <nav>
          <Link to="/" className="nav-link" activeProps={{ className: "active" }}>
            Gallery
          </Link>
          <Link to="/upload" className="nav-link" activeProps={{ className: "active" }}>
            Upload
          </Link>
          <Link to="/status" className="nav-link" activeProps={{ className: "active" }}>
            Status
          </Link>
        </nav>
      </header>
      <main>
        <Outlet />
      </main>
    </div>
  );
}
