import airflow
from airflow import models, settings
from airflow.contrib.auth.backends.password_auth import PasswordUser
user = PasswordUser(models.User())
user.username = 'spinapp-airflow'
user.email = 'partner_sho.suzuki@opt.ne.jp'
user._set_password = 'spinapp-airflow-password'.encode('utf8')
session = settings.Session()
session.add(user)
session.commit()
session.close()
exit()
