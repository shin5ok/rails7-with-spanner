from diagrams import Cluster, Diagram
from diagrams.gcp.analytics import BigQuery
from diagrams.gcp.compute import Run
from diagrams.gcp.network import LoadBalancing
from diagrams.gcp.database import Spanner, Memorystore

with Diagram("Game Application", show=False):

    lb = LoadBalancing("Google Cloud Load Balancing")

    with Cluster("Application"):
        run = Run("user-api")
        spanner = Spanner("game")
    
    with Cluster("Cache Layer"):
        with Cluster("VPC"):
            redis = Memorystore("Redis")
    
    lb >> run
    run >> spanner
    run >> redis
