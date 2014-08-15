"""
Package with OpenStack resources export/import utilities.
"""
from migrationlib.os import osCommon
from utils import log_step, get_log
import sqlalchemy

LOG = get_log(__name__)


class ResourceExporter(osCommon.osCommon):
    """
    Exports various cloud resources (tenants, users, flavors, etc.) to a container
    to be later imported by ResourceImporter
    """

    def __init__(self, conf):
        self.data = dict()
        self.config = conf['clouds']['from']
        self.funcs = []
        super(ResourceExporter, self).__init__(self.config)

    def convert_to_dict(self):
        res = {'data': self.data}
        res['_type_class'] = ResourceExporter.__name__
        return res

    @log_step(LOG)
    def get_flavors(self):
        def process_flavor(flavor):
            if flavor.is_public:
                return flavor, []
            else:
                tenants = self.nova_client.flavor_access.list(flavor=flavor)
                tenants = [self.keystone_client.tenants.get(t.tenant_id).name for t in tenants]
                return flavor, tenants

        self.data['flavors'] = map(process_flavor, self.nova_client.flavors.list(is_public=False))
        return self

    @log_step(LOG)
    def get_tenants(self):
        self.data['tenants'] = self.keystone_client.tenants.list()
        return self

    @log_step(LOG)
    def get_roles(self):
        self.data['roles'] = self.keystone_client.roles.list()
        return self

    @log_step(LOG)
    def get_user_info(self):
        self.__get_user_info(self.config['keep_user_passwords'])
        return self

    @log_step(LOG)
    def get_security_groups(self):
        network_service = self.config['network_service']
        security_groups = self.__get_neutron_security_groups() \
            if network_service == "neutron" else \
            self.__get_nova_security_groups()
        self.data['security_groups_info'] = {'service': network_service, 'security_groups': security_groups}
        return self

    def __get_nova_security_groups(self):
        return self.nova_client.security_groups.list()

    def __get_neutron_security_groups(self):
        return self.network_client.list_security_groups()['security_groups']

    def __get_user_info(self, with_password):
        users = self.keystone_client.users.list()
        info = {}
        if with_password:
            with sqlalchemy.create_engine(self.keystone_db_conn_url).begin() as connection:
                for user in users:
                    for password in connection.execute(sqlalchemy.text("SELECT password FROM user WHERE id = :user_id"),
                                                       user_id=user.id):
                        info[user.name] = password[0]
        self.data['users'] = info

    @log_step(LOG)
    def build(self):
        return self.data

