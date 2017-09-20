import argparse
import json
import os

from airflow import models, settings
from airflow.contrib.auth.backends.password_auth import PasswordUser


def create_admin_user(admin_user):
    """
    Create a user in Airflow metadata database to allow login with password_auth backend.

    :param admin_user: User properties as dictionary.
    :return: Job done.
    """
    print('Creating admin user...')
    user = PasswordUser(models.User())
    user.username = admin_user['username']
    user.password = admin_user['password']
    user.email = admin_user['email']

    session = settings.Session()
    try:
        existing = session.query(models.User).filter_by(username=user.username).first()
        if not existing:
            session.add(user)
            session.commit()
            print('\tCREATED: Admin user %s' % user.username)
        else:
            print('\tSKIPPED: Admin user %s already exists' % user.username)
    finally:
        session.close()


def update_connections(connections):
    """
    Add or update Airflow connections.

    :param connections: Connections as dictionary.
    :return: Job done.
    """
    print('Updating connections...')
    session = settings.Session()
    try:
        for conn_id, conn in connections.items():
            existing = session.query(models.Connection).filter_by(conn_id=conn_id).first()
            if existing:
                existing.host = conn['host']
                existing.conn_type = conn['conn_type']

                existing.port = conn.get('port')
                existing.login = conn.get('login')
                existing.password = conn.get('password')
                existing.schema = conn.get('schema')
                existing.extra = conn.get('extra')
                session.merge(existing)
                print('\tUPDATED: connection %s' % conn_id)
            else:
                c = models.Connection(conn_id=conn_id, **conn)
                session.add(c)
                print('\tADDED: connection %s' % conn_id)

        session.commit()
        print('Changes commited.')
    finally:
        session.close()


def update_variables(variables):
    """
    Add or update Airflow variables.

    :param variables: Variables as dictionary.
    :return: Job done.
    """
    print('Updating variables...')
    session = settings.Session()
    try:
        for k, v in variables.items():
            existing = session.query(models.Variable).filter_by(key=k).first()
            if existing:
                existing.val = v
                session.merge(existing)
                print('\tUPDATED: variable %s' % k)
            else:
                var = models.Variable(key=k, val=v)
                session.add(var)
                print('\tADDED: variable %s' % k)

        session.commit()
        print('Changes commited.')
    finally:
        session.close()


# All parameters are optional in order to execute partial updates.
parser = argparse.ArgumentParser()
parser.add_argument('--connections', type=str, help='Connections JSON file path.', required=False)
parser.add_argument('--variables', type=str, help='Variables JSON file path.', required=False)
parser.add_argument('--admin', type=str, help='Admin user JSON file path.', required=False)
args = parser.parse_args()

print('Initializing metadata database...')


def _load_as_json(path):
    with open(path, 'rt') as rt:
        return json.loads(rt.read())


if args.admin and os.path.isfile(args.admin):
    create_admin_user(_load_as_json(args.admin))

if args.connections and os.path.isfile(args.connections):
    update_connections(_load_as_json(args.connections))

if args.variables and os.path.isfile(args.variables):
    update_variables(_load_as_json(args.variables))

print('=======================')
