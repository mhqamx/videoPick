from mangum import Mangum
from app.main import app

lambda_handler = Mangum(app, lifespan="off")
