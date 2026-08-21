from datetime import datetime

from airflow import DAG
from airflow.decorators import task
from airflow.operators.bash import BashOperator


with DAG(
    dag_id="mlops_services_smoke",
    description="Platform smoke DAG that verifies Airflow scheduling and task execution.",
    start_date=datetime(2022, 1, 1),
    schedule=None,
    catchup=False,
    is_paused_upon_creation=False,
    tags=["mlops-services", "smoke"],
) as dag:
    hello = BashOperator(
        task_id="hello",
        bash_command="echo hello",
    )

    @task(task_id="airflow")
    def airflow_task() -> None:
        print("airflow")

    hello >> airflow_task()
