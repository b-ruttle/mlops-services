import hmac
import os
from functools import wraps

import requests
from flask import Flask, flash, redirect, render_template, request, session, url_for
from sqlalchemy import MetaData, Table, create_engine, inspect, select
from sqlalchemy.exc import SQLAlchemyError
from werkzeug.middleware.proxy_fix import ProxyFix


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


APP_USERNAME = _env("MLFLOW_ADMIN_APP_USERNAME", "adminapp")
APP_PASSWORD = os.getenv("MLFLOW_ADMIN_APP_PASSWORD", "change_me_admin_app_password")
APP_SECRET_KEY = os.getenv(
    "MLFLOW_ADMIN_APP_SECRET_KEY", "change_me_mlflow_admin_app_secret_key"
)
MLFLOW_UPSTREAM_URL = _env("MLFLOW_ADMIN_UPSTREAM_URL", "http://mlflow:5000").rstrip("/")
MLFLOW_SERVICE_USERNAME = _env("MLFLOW_ADMIN_SERVICE_USERNAME", "admin")
MLFLOW_SERVICE_PASSWORD = os.getenv("MLFLOW_ADMIN_SERVICE_PASSWORD", "")
MLFLOW_HTTP_TIMEOUT = float(_env("MLFLOW_ADMIN_HTTP_TIMEOUT", "10"))
MLFLOW_AUTH_DB_URI = _env("MLFLOW_ADMIN_AUTH_DB_URI", _env("MLFLOW_AUTH_DATABASE_URI", ""))
MLFLOW_AUTH_DB_TIMEOUT = int(_env("MLFLOW_ADMIN_AUTH_DB_TIMEOUT", "5"))

app = Flask(__name__)
app.secret_key = APP_SECRET_KEY
# Trust nginx forwarding headers so generated URLs stay under /mlflow-admin.
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)


class MlflowAdminApiError(Exception):
    pass


class MlflowAuthDbError(Exception):
    pass


def _to_bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if value is None:
        return False
    return str(value).strip().lower() in {"1", "true", "t", "yes", "y", "on"}


def _build_auth_db_engine():
    if not MLFLOW_AUTH_DB_URI:
        return None, "MLFLOW_ADMIN_AUTH_DB_URI is required."

    if not MLFLOW_AUTH_DB_URI.startswith("postgresql+psycopg2://"):
        return (
            None,
            "MLFLOW_ADMIN_AUTH_DB_URI must be a Postgres SQLAlchemy URI "
            "(postgresql+psycopg2://...).",
        )

    connect_args = {"connect_timeout": MLFLOW_AUTH_DB_TIMEOUT}

    try:
        return (
            create_engine(
                MLFLOW_AUTH_DB_URI,
                connect_args=connect_args,
                future=True,
                pool_pre_ping=True,
            ),
            None,
        )
    except Exception as exc:  # pragma: no cover
        return None, str(exc)


AUTH_DB_ENGINE, AUTH_DB_ENGINE_ERROR = _build_auth_db_engine()

PERMISSIONS_DOCS_URL = "https://mlflow.org/docs/latest/self-hosting/security/basic-http-auth/"
ROLE_ADMIN = "ADMIN"
ROLE_OPTIONS = (
    {"value": ROLE_ADMIN, "label": "Admin", "summary": "Full access to all resources and user admin actions."},
    {"value": "MANAGE", "label": "Manage", "summary": "Can read, update, delete, and manage permissions on resources."},
    {"value": "EDIT", "label": "Edit", "summary": "Can read and modify resources, but cannot manage permissions."},
    {"value": "READ", "label": "Read", "summary": "Can only view resources and metadata."},
    {"value": "NO_PERMISSIONS", "label": "No Permissions", "summary": "No access to resources."},
)
ROLE_VALUES = {option["value"] for option in ROLE_OPTIONS}
PERMISSION_MATRIX = (
    {
        "permission": "READ",
        "read": "Yes",
        "use": "No",
        "update": "No",
        "delete": "No",
        "manage": "No",
    },
    {
        "permission": "USE",
        "read": "Yes",
        "use": "Yes",
        "update": "No",
        "delete": "No",
        "manage": "No",
    },
    {
        "permission": "EDIT",
        "read": "Yes",
        "use": "Yes",
        "update": "Yes",
        "delete": "No",
        "manage": "No",
    },
    {
        "permission": "MANAGE",
        "read": "Yes",
        "use": "Yes",
        "update": "Yes",
        "delete": "Yes",
        "manage": "Yes",
    },
    {
        "permission": "NO_PERMISSIONS",
        "read": "No",
        "use": "No",
        "update": "No",
        "delete": "No",
        "manage": "No",
    },
)


def _api_error(response: requests.Response) -> str:
    try:
        payload = response.json()
    except ValueError:
        payload = response.text
    return f"HTTP {response.status_code}: {payload}"


def mlflow_api_request(method: str, path: str, **kwargs):
    url = f"{MLFLOW_UPSTREAM_URL}{path}"
    try:
        response = requests.request(
            method,
            url,
            auth=(MLFLOW_SERVICE_USERNAME, MLFLOW_SERVICE_PASSWORD),
            timeout=MLFLOW_HTTP_TIMEOUT,
            **kwargs,
        )
    except requests.RequestException as exc:
        raise MlflowAdminApiError(str(exc)) from exc

    if response.status_code >= 400:
        raise MlflowAdminApiError(_api_error(response))

    if not response.content:
        return {}

    try:
        return response.json()
    except ValueError:
        return {}


def _permission_column_name(column_names):
    if "permission" in column_names:
        return "permission"
    for name in column_names:
        if "permission" in name:
            return name
    return None


def _resource_column_name(table_name, column_names):
    if "experiment" in table_name:
        preferred = ("experiment_id", "name", "resource", "resource_id")
    elif "model" in table_name:
        preferred = ("name", "registered_model_name", "model_name", "resource", "resource_id")
    else:
        preferred = ("name", "resource", "resource_id", "experiment_id")

    for name in preferred:
        if name in column_names:
            return name
    return None


def search_users_via_auth_db(username_filter: str = ""):
    if AUTH_DB_ENGINE is None:
        raise MlflowAuthDbError("No auth DB URI configured for mlflow-admin.")

    metadata = MetaData()

    try:
        with AUTH_DB_ENGINE.connect() as conn:
            inspector = inspect(conn)
            table_names = set(inspector.get_table_names())
            if "users" not in table_names:
                raise MlflowAuthDbError("Auth DB table 'users' was not found.")

            users_table = Table("users", metadata, autoload_with=conn)
            if "username" not in users_table.c:
                raise MlflowAuthDbError("Auth DB table 'users' is missing 'username'.")

            select_columns = [users_table.c.username]
            has_user_id = "id" in users_table.c
            has_is_admin = "is_admin" in users_table.c
            if has_user_id:
                select_columns.append(users_table.c.id.label("user_id"))
            if has_is_admin:
                select_columns.append(users_table.c.is_admin)

            query = select(*select_columns).order_by(users_table.c.username.asc())
            if username_filter:
                pattern = f"%{username_filter}%"
                query = query.where(users_table.c.username.ilike(pattern))

            user_rows = conn.execute(query).mappings().all()

            users_by_username = {}
            username_by_id = {}
            for row in user_rows:
                username = (row.get("username") or "").strip()
                if not username:
                    continue
                users_by_username[username] = {
                    "username": username,
                    "is_admin": _to_bool(row.get("is_admin")),
                    "experiment_permissions": [],
                    "registered_model_permissions": [],
                    "other_permissions": [],
                    "data_source": "auth-db",
                }
                if has_user_id:
                    user_id = row.get("user_id")
                    if user_id is not None:
                        username_by_id[user_id] = username

            permission_tables = [name for name in table_names if name.endswith("_permissions")]
            for table_name in permission_tables:
                permissions_table = Table(table_name, metadata, autoload_with=conn)
                column_names = list(permissions_table.c.keys())

                if "username" in column_names:
                    user_column = "username"
                elif "user_id" in column_names:
                    user_column = "user_id"
                else:
                    continue

                permission_column = _permission_column_name(column_names)
                resource_column = _resource_column_name(table_name, column_names)

                permission_select = [permissions_table.c[user_column].label("user_ref")]
                if resource_column:
                    permission_select.append(permissions_table.c[resource_column].label("resource_ref"))
                if permission_column:
                    permission_select.append(permissions_table.c[permission_column].label("permission_ref"))

                for row in conn.execute(select(*permission_select)).mappings():
                    user_ref = row.get("user_ref")
                    if user_column == "user_id":
                        username = username_by_id.get(user_ref)
                    else:
                        username = str(user_ref) if user_ref is not None else None

                    if not username or username not in users_by_username:
                        continue

                    permission = row.get("permission_ref")
                    resource = row.get("resource_ref")
                    permission_text = str(permission) if permission is not None else "UNKNOWN"
                    resource_text = str(resource) if resource is not None else "*"
                    entry = f"{resource_text}:{permission_text}"

                    if "experiment" in table_name:
                        users_by_username[username]["experiment_permissions"].append(entry)
                    elif "model" in table_name:
                        users_by_username[username]["registered_model_permissions"].append(entry)
                    else:
                        users_by_username[username]["other_permissions"].append(
                            f"{table_name}:{entry}"
                        )

            users = []
            for username in sorted(users_by_username):
                user = users_by_username[username]
                for key in (
                    "experiment_permissions",
                    "registered_model_permissions",
                    "other_permissions",
                ):
                    values = sorted(set(user[key]))
                    user[key] = values
                    user[f"{key}_text"] = ", ".join(values) if values else "-"

                user["total_permissions"] = (
                    len(user["experiment_permissions"])
                    + len(user["registered_model_permissions"])
                    + len(user["other_permissions"])
                )
                permission_values = {
                    entry.rsplit(":", 1)[-1]
                    for entry in (
                        user["experiment_permissions"]
                        + user["registered_model_permissions"]
                        + user["other_permissions"]
                    )
                    if ":" in entry
                }
                if user.get("is_admin"):
                    global_permission = ROLE_ADMIN
                elif not permission_values:
                    global_permission = "UNSET"
                elif len(permission_values) == 1:
                    global_permission = next(iter(permission_values))
                else:
                    global_permission = "MIXED"
                user["global_permission"] = global_permission
                user["suggested_role"] = (
                    global_permission if global_permission in ROLE_VALUES else "READ"
                )
                users.append(user)

            return users
    except SQLAlchemyError as exc:
        raise MlflowAuthDbError(str(exc)) from exc


def list_users(username_filter: str = ""):
    if AUTH_DB_ENGINE_ERROR:
        return [], f"Auth DB config failed: {AUTH_DB_ENGINE_ERROR}", "auth-db"

    try:
        return search_users_via_auth_db(username_filter), None, "auth-db"
    except MlflowAuthDbError as exc:
        return [], f"Auth DB listing failed: {exc}", "auth-db"


def _normalized_role(raw_role: str) -> str:
    role = (raw_role or "").strip().upper()
    if role == "NONE":
        role = "NO_PERMISSIONS"
    if role not in ROLE_VALUES:
        raise MlflowAdminApiError(f"Unsupported role '{raw_role}'.")
    return role


def _search_all(path: str, items_key: str, item_key: str, request_method: str = "POST"):
    results = []
    next_page_token = None

    while True:
        payload = {"max_results": 200}
        if next_page_token:
            payload["page_token"] = next_page_token

        if request_method == "GET":
            data = mlflow_api_request("GET", path, params=payload)
        else:
            data = mlflow_api_request("POST", path, json=payload)

        for item in data.get(items_key, []):
            value = item.get(item_key)
            if value not in (None, ""):
                results.append(str(value))

        next_page_token = data.get("next_page_token")
        if not next_page_token:
            break

    return sorted(set(results))


def _upsert_permission(create_path: str, update_path: str, payload: dict):
    try:
        mlflow_api_request("POST", create_path, json=payload)
        return
    except MlflowAdminApiError as create_error:
        try:
            mlflow_api_request("PATCH", update_path, json=payload)
            return
        except MlflowAdminApiError as update_error:
            raise MlflowAdminApiError(
                f"{create_error}; update fallback failed: {update_error}"
            ) from update_error


def _delete_permission(delete_path: str, payload: dict):
    try:
        mlflow_api_request("DELETE", delete_path, json=payload)
    except MlflowAdminApiError as exc:
        # Deleting a user should be idempotent against stale ACL references.
        if "HTTP 404" in str(exc):
            return
        raise


def _get_user_permission_targets(username: str):
    data = mlflow_api_request(
        "GET", "/api/2.0/mlflow/users/get", params={"username": username}
    )
    user = data.get("user", {})
    experiment_ids = sorted(
        {
            str(entry.get("experiment_id"))
            for entry in user.get("experiment_permissions", [])
            if entry.get("experiment_id") not in (None, "")
        }
    )
    model_names = sorted(
        {
            str(entry.get("name"))
            for entry in user.get("registered_model_permissions", [])
            if entry.get("name") not in (None, "")
        }
    )
    return experiment_ids, model_names


def _delete_user_permissions(username: str):
    experiment_ids, model_names = _get_user_permission_targets(username)

    for experiment_id in experiment_ids:
        _delete_permission(
            "/api/2.0/mlflow/experiments/permissions/delete",
            {"experiment_id": experiment_id, "username": username},
        )

    for model_name in model_names:
        _delete_permission(
            "/api/2.0/mlflow/registered-models/permissions/delete",
            {"name": model_name, "username": username},
        )

    return {"experiments": len(experiment_ids), "models": len(model_names)}


def apply_role_to_user(username: str, role: str):
    normalized_role = _normalized_role(role)
    is_admin = normalized_role == ROLE_ADMIN

    mlflow_api_request(
        "PATCH",
        "/api/2.0/mlflow/users/update-admin",
        json={"username": username, "is_admin": is_admin},
    )

    if is_admin:
        return {"experiments": 0, "models": 0}

    experiment_ids = _search_all(
        "/api/2.0/mlflow/experiments/search", "experiments", "experiment_id"
    )
    model_names = _search_all(
        "/api/2.0/mlflow/registered-models/search",
        "registered_models",
        "name",
        request_method="GET",
    )

    for experiment_id in experiment_ids:
        _upsert_permission(
            "/api/2.0/mlflow/experiments/permissions/create",
            "/api/2.0/mlflow/experiments/permissions/update",
            {
                "experiment_id": experiment_id,
                "username": username,
                "permission": normalized_role,
            },
        )

    for model_name in model_names:
        _upsert_permission(
            "/api/2.0/mlflow/registered-models/permissions/create",
            "/api/2.0/mlflow/registered-models/permissions/update",
            {
                "name": model_name,
                "username": username,
                "permission": normalized_role,
            },
        )

    return {"experiments": len(experiment_ids), "models": len(model_names)}


def login_required(view_func):
    @wraps(view_func)
    def wrapped_view(*args, **kwargs):
        if not session.get("logged_in"):
            return redirect(url_for("login"))
        return view_func(*args, **kwargs)

    return wrapped_view


@app.route("/login", methods=["GET", "POST"])
def login():
    if session.get("logged_in"):
        return redirect(url_for("index"))

    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        username_ok = hmac.compare_digest(username, APP_USERNAME)
        password_ok = hmac.compare_digest(password, APP_PASSWORD)

        if username_ok and password_ok:
            session.clear()
            session["logged_in"] = True
            session["username"] = username
            return redirect(url_for("index"))

        flash("Invalid admin app credentials.", "error")

    return render_template("login.html")


@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.get("/")
@login_required
def index():
    users, warning, user_source = list_users("")
    admin_count = sum(1 for user in users if user.get("is_admin"))
    total_permissions = sum(user.get("total_permissions", 0) for user in users)
    return render_template(
        "index.html",
        users=users,
        warning=warning,
        service_username=MLFLOW_SERVICE_USERNAME,
        user_source=user_source,
        users_count=len(users),
        admin_count=admin_count,
        total_permissions=total_permissions,
        role_options=ROLE_OPTIONS,
        permission_matrix=PERMISSION_MATRIX,
        permissions_docs_url=PERMISSIONS_DOCS_URL,
    )


@app.post("/users/create")
@login_required
def create_user():
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")
    role = request.form.get("role", "READ")

    if not username or not password:
        flash("Username and password are required.", "error")
        return redirect(url_for("index"))

    try:
        normalized_role = _normalized_role(role)
        if username == MLFLOW_SERVICE_USERNAME and normalized_role != ROLE_ADMIN:
            raise MlflowAdminApiError(
                "Refusing to create the service account with a non-admin role."
            )
        mlflow_api_request(
            "POST",
            "/api/2.0/mlflow/users/create",
            json={"username": username, "password": password},
        )
        affected = apply_role_to_user(username, normalized_role)
        if normalized_role == ROLE_ADMIN:
            flash(f"Created user '{username}' with role ADMIN.", "success")
        else:
            flash(
                "Created user '{}' with role {} (applied to {} experiments and {} models).".format(
                    username,
                    normalized_role,
                    affected["experiments"],
                    affected["models"],
                ),
                "success",
            )
    except MlflowAdminApiError as exc:
        flash(f"Failed to create user '{username}': {exc}", "error")

    return redirect(url_for("index"))


@app.post("/users/set-role")
@login_required
def set_role():
    username = request.form.get("username", "").strip()
    role = request.form.get("role", "READ")

    if not username:
        flash("Username is required.", "error")
        return redirect(url_for("index"))

    try:
        normalized_role = _normalized_role(role)
        if username == MLFLOW_SERVICE_USERNAME and normalized_role != ROLE_ADMIN:
            raise MlflowAdminApiError(
                "Refusing to downgrade the MLflow service account from ADMIN."
            )
        affected = apply_role_to_user(username, normalized_role)
        if normalized_role == ROLE_ADMIN:
            flash(f"Updated '{username}' to role ADMIN.", "success")
        else:
            flash(
                "Updated '{}' to role {} (applied to {} experiments and {} models).".format(
                    username,
                    normalized_role,
                    affected["experiments"],
                    affected["models"],
                ),
                "success",
            )
    except MlflowAdminApiError as exc:
        flash(f"Failed to update role for '{username}': {exc}", "error")

    return redirect(url_for("index"))


@app.post("/users/reset-password")
@login_required
def reset_password():
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "")

    if not username or not password:
        flash("Username and new password are required.", "error")
        return redirect(url_for("index"))

    try:
        mlflow_api_request(
            "PATCH",
            "/api/2.0/mlflow/users/update-password",
            json={"username": username, "password": password},
        )
        flash(f"Password reset for '{username}'.", "success")
    except MlflowAdminApiError as exc:
        flash(f"Failed to reset password for '{username}': {exc}", "error")

    return redirect(url_for("index"))


@app.post("/users/delete")
@login_required
def delete_user():
    username = request.form.get("username", "").strip()

    if not username:
        flash("Username is required.", "error")
        return redirect(url_for("index"))

    if username == MLFLOW_SERVICE_USERNAME:
        flash(
            "Refusing to delete the MLflow service account used by this app.",
            "error",
        )
        return redirect(url_for("index"))

    try:
        cleared = _delete_user_permissions(username)
        mlflow_api_request(
            "DELETE",
            "/api/2.0/mlflow/users/delete",
            json={"username": username},
        )
        flash(
            "Deleted user '{}' (removed {} experiment ACLs and {} model ACLs first).".format(
                username,
                cleared["experiments"],
                cleared["models"],
            ),
            "success",
        )
    except MlflowAdminApiError as exc:
        flash(f"Failed to delete user '{username}': {exc}", "error")

    return redirect(url_for("index"))


if __name__ == "__main__":
    port = int(_env("MLFLOW_ADMIN_PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
