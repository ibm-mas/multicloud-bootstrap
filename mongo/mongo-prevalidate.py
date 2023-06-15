import pymongo
import sys
import os

MONGO_ADMIN_USERNAME = os.getenv('MONGO_ADMIN_USERNAME')
MONGO_ADMIN_PASSWORD = os.getenv('MONGO_ADMIN_PASSWORD')
MONGO_HOSTS = os.getenv('MONGO_HOSTS')
RETRY_WRITES = os.getenv('RETRY_WRITES')
GIT_REPO_HOME = os.getenv('GIT_REPO_HOME')
print(f'mongo-prevalidate : RETRY_WRITES={RETRY_WRITES}')

CONNECTION_STRING=f'mongodb://{MONGO_ADMIN_USERNAME}:{MONGO_ADMIN_PASSWORD}@{MONGO_HOSTS}/?tls=true&tlsCAFile={GIT_REPO_HOME}/mongo/mongo-ca.pem&retryWrites={RETRY_WRITES}'
print(f'CONNECTION_STRING {CONNECTION_STRING}')
client = pymongo.MongoClient(CONNECTION_STRING)

if client :
    print("Connection to mongodb success !")
else:
    print("Connection to mongodb failed !")    
    os._exit(38)

##Specify the database to be used
db = client.sample_database

##Specify the collection to be used
col = db.sample_collection

##Insert a single document
col.insert_one({'hello':'Amazon DocumentDB'})

##Find the document that was previously written
x = col.find_one({'hello':'Amazon DocumentDB'})

##Print the result to the screen
print(x)

if client :
    print("Connection to mongodb success !")
    client.close()
    os._exit(0)
else:
    print("Connection to mongodb failed !")    
    os._exit(38)