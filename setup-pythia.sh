#!/bin/bash

set -x

DIRNAME=`dirname $0`

# Grab our libs
. "$DIRNAME/setup-lib.sh"
# Don't run setup-pythia.sh twice
if [ -f $OURDIR/setup-pythia-done ]; then
    echo "setup-pythia already ran; not running again"
    exit 0
fi

logtstart "pythia"

#
# openstack CLI commands seem flakey sometimes on Kilo and Liberty.
# Don't know if it's WSGI, mysql dropping connections, an NTP
# thing... but until it gets solved more permanently, have to retry :(.
#
__openstack() {
    __err=1
    __debug=
    __times=0
    while [ $__times -lt 16 -a ! $__err -eq 0 ]; do
	openstack $__debug "$@"
	__err=$?
        if [ $__err -eq 0 ]; then
            break
        fi
	__debug=" --debug "
	__times=`expr $__times + 1`
	if [ $__times -gt 1 ]; then
	    echo "ERROR: openstack command failed: sleeping and trying again!"
	    sleep 8
	fi
    done
}

if [ -f $SETTINGS ]; then
    . $SETTINGS
fi

maybe_install_packages pssh
PSSH='/usr/bin/parallel-ssh -t 0 -O StrictHostKeyChecking=no '
PSCP='/usr/bin/parallel-scp -t 0 -O StrictHostKeyChecking=no '

cd /local

PHOSTS=""
mkdir -p $OURDIR/pssh.setup-pythia.stdout $OURDIR/pssh.setup-pythia.stderr

for node in $COMPUTENODES
do
    fqdn=`getfqdn $node`
    PHOSTS="$PHOSTS -H $fqdn"
done

echo "*** Setting up Pythia on compute nodes: $PHOSTS"
$PSSH -v $PHOSTS -o $OURDIR/pssh.setup-pythia.stdout \
    -e $OURDIR/pssh.setup-pythia.stderr $DIRNAME/setup-pythia-compute.sh

echo "*** Installing Rust"
maybe_install_packages python3-pip

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
rustup component add rls

cargo install --path /local/reconstruction
echo "*** Finished installing Rust"

mkdir -p /opt/stack/manifest
mkdir -p /opt/stack/reconstruction
chmod -R g+rwX /opt/
chmod -R o+rwX /opt/
maybe_install_packages redis-server python-redis python3-redis python3-pip
service_start redis

profiler_conf=$(cat <<END
[profiler]
enabled = True
connection_string = redis://localhost:6379
hmac_keys = Devstack1
trace_wsgi_transport = True
trace_message_store = True
trace_management_store = True
trace_sqlalchemy = False
END
)

echo "$profiler_conf" >> /etc/nova/nova.conf
echo "$profiler_conf" >> /etc/keystone/keystone.conf
echo "$profiler_conf" >> /etc/cinder/cinder.conf
echo "$profiler_conf" >> /etc/neutron/neutron.conf
echo "$profiler_conf" >> /etc/glance/glance-api.conf

for project in "osprofiler" "osc_lib" "python-openstackclient" "nova" "oslo.messaging" "neutron"
do
    pip3 install --force-reinstall --no-deps -U /local/$project
done

chmod o+rX /etc/nova
chmod g+rX /etc/nova
chmod o+r /etc/nova/nova.conf
chmod g+r /etc/nova/nova.conf

service_restart apache2.service
service_restart ceilometer-agent-central.service
service_restart ceilometer-agent-notification.service
service_restart cinder-scheduler.service
service_restart cinder-volume.service
service_restart designate-api.service
service_restart designate-central.service
service_restart designate-mdns.service
service_restart designate-producer.service
service_restart designate-worker.service
service_restart glance-api.service
service_restart gnocchi-metricd.service
service_restart heat-api-cfn.service
service_restart heat-api.service
service_restart heat-engine.service
service_restart magnum-api.service
service_restart magnum-conductor.service
service_restart manila-api.service
service_restart manila-scheduler.service
service_restart manila-share.service
service_restart memcached.service
service_restart neutron-dhcp-agent.service
service_restart neutron-l3-agent.service
service_restart neutron-lbaasv2-agent.service
service_restart neutron-metadata-agent.service
service_restart neutron-metering-agent.service
service_restart neutron-openvswitch-agent.service
service_restart neutron-ovs-cleanup.service
service_restart neutron-server.service
service_restart nginx.service
service_restart nova-api.service
service_restart nova-conductor.service
service_restart nova-consoleauth.service
service_restart nova-novncproxy.service
service_restart nova-scheduler.service
service_restart rabbitmq-server.service
service_restart redis-server.service
service_restart sahara-engine.service
service_restart swift-account-auditor.service
service_restart swift-account-reaper.service
service_restart swift-account-replicator.service
service_restart swift-account.service
service_restart swift-container-auditor.service
service_restart swift-container-replicator.service
service_restart swift-container-sync.service
service_restart swift-container-updater.service
service_restart swift-container.service
service_restart swift-object-auditor.service
service_restart swift-object-reconstructor.service
service_restart swift-object-replicator.service
service_restart swift-object-updater.service
service_restart swift-object.service
service_restart swift-proxy.service
service_restart trove-api.service
service_restart trove-conductor.service
service_restart trove-taskmanager.service

wget https://download.cirros-cloud.net/0.4.0/cirros-0.4.0-${ARCH}-disk.img
openstack image create --file cirros-0.4.0-${ARCH}-disk.img cirros

ln -s /local/reconstruction/Settings.toml /opt/stack/reconstruction/

touch $OURDIR/setup-pythia-done
logtend "pythia"
exit 0