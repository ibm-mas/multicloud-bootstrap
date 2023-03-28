import jaydebeapi
import os
con=jaydebeapi.connect('oracle.jdbc.driver.OracleDriver',
                        os.getenv('MAS_JDBC_URL'),
                        {'user':os.getenv('MAS_JDBC_USER'),
                        'password':os.getenv('MAS_JDBC_PASSWORD')},
                        jars=os.getenv('MAS_ORACLE_JAR_LOCAL_PATH'),)

if con :
#    print("Connected to db successfully !")
    con.close()
    os._exit(0)
else:
    os._exit(1)
