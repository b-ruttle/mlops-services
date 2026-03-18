from datetime import datetime

from airflow import DAG
from airflow.decorators import task
from airflow.operators.bash import BashOperator


with DAG(
    dag_id="demo",
    description="Simple demo DAG to verify Airflow is scheduling and running tasks.",
    start_date=datetime(2022, 1, 1),
    schedule=None,
    catchup=False,
    is_paused_upon_creation=False,
    tags=["demo"],
) as dag:
    hello = BashOperator(
        task_id="hello",
        bash_command="echo hello",
    )

    @task(task_id="airflow")
    def airflow_task() -> None:
        print("airflow")

    hello >> airflow_task()
