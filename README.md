# Setting Up the Infrastructure in Azure

To set up the infrastructure, run `terraform apply`. It will create an AKS cluster, and an Azure VM in the same VNet. Once it completes, it will output a `kubeconfig` filecontents, which should be merged into your `~/.kube/config` file. Once it has been merged, set the `kubectl` `cluster` and `context`.

```
$ kubectl config set-cluster neil-test-k8s
$ kubectl config set-context neil-test-k8s
```

The Kubernetes dashboard should be available if you run: 

```
$ az aks browse --resource-group neil-test-k8s-resources --name neil-test-k8s
```

# Setting up the Consul Server Cluster in Azure

Using [this repo](https://github.com/hashicorp/consul-helm), you just need to change a few config options. Find an example below. 

```
global:
  enabled: true
  image: "hashicorp/consul-enterprise:1.4.4-ent"
  domain: consul
  datacenter: dc1

server:
  enabled: true
  replicas: 1
  bootstrapExpect: 1
  storage: 10Gi
  enterpriseLicense:
    secretName: "consul-ent-license"
    secretKey: "key"

client:
  enabled: true

dns:
  enabled: true

ui:
  enabled: true
  service:
    enabled: true
    type: LoadBalancer
```

Now add the license as a secret, initialize the chart, and install the chart.

```
$ secret=$(cat 96c51187-fce0-b0de-2df1-f2878f9dac41.hclic)
$ kubectl create secret generic consul-ent-license --from-literal="key=${secret}"

$ helm init --wait 
$ helm install -f helm-consul-values.yaml --name=neil-test --wait ./;
```

Once the chart has finished installing, you should be able to see pods.

```
$ kubectl get pods
NAME                        READY     STATUS    RESTARTS   AGE
neil-test-consul-server-0   1/1       Running   0          51m
neil-test-consul-tv9xl      1/1       Running   0          51m
```

And you can confirm Consul is running correctly.

```
$ kubectl exec neil-test-consul-server-0 -- consul members
Node                       Address            Status  Type    Build      Protocol  DC   Segment
neil-test-consul-server-0  10.139.11.14:8301  alive   server  1.4.4+ent  2         dc1  <all>
aks-default-92674352-0     10.139.11.24:8301  alive   client  1.4.4+ent  2         dc1  <default>
neil-test-vm               10.139.1.4:8301    alive   client  1.4.4+ent  2         dc1  <default>
```

# Install and Run a Simple Consul on the VM and Join the Cluster

SSH into the VM that was created using the username and password defined. Once there, download Consul Enterprise:

```
$ wget https://s3-us-west-2.amazonaws.com/hc-enterprise-binaries/consul/ent/1.4.4/consul-enterprise_1.4.4%2Bent_linux_amd64.zip
$ unzip consul-enterprise_1.4.4+ent_linux_amd64.zip
$ sudo mv consul /usr/local/bin/
```

Now that `consul` is installed, you need to setup some simple config.

```
mkdir -p /tmp/consul/data_dir
touch /tmp/consul/consul.json
```

After creating the config file, add these contents:

```
{
  "datacenter": "dc1",
  "node_name": "neil-test-vm",
  "log_level": "INFO",
  "client_addr": "0.0.0.0",
  "ui": true
}
```

With the configuration in place, you can start the agent now. There are two methodologies here. 

### Join the Cluster Manually
Start the Consul agent with the following:

```
consul agent -config-file=/tmp/consul/consul.json  -data-dir=/tmp/consul/data
```

Once it has started, reconfirm the address of the member you want to join. In this case, use the server from the following:

```
$ kubectl exec neil-test-consul-server-0 -- consul members
Node                       Address            Status  Type    Build      Protocol  DC   Segment
neil-test-consul-server-0  10.139.11.14:8301  alive   server  1.4.4+ent  2         dc1  <all>
aks-default-92674352-0     10.139.11.24:8301  alive   client  1.4.4+ent  2         dc1  <default>
neil-test-vm               10.139.1.4:8301    alive   client  1.4.4+ent  2         dc1  <default>
```

With that IP address, you can join with:

```
consul join 10.139.11.14
```

And your VM should be connected to your cluster.

### Join the Cluster Automatically

To have the agent join the automatically, there are a few more steps. First, you'll need to copy the `kubeconfig` output from Terraform (or from your local `~/.kube/config`) and place it in `~/.kube/config` on the VM. This is important as this is how Consul will auto-discover the appropriate Kubernetes resources. Once that is in place, you can start the agent with the following additional option, and you should automatically connect based on the labels of the pod.

```
consul agent -config-file=/tmp/consul/consul.json  -data-dir=/tmp/consul/data -retry-join 'provider=k8s label_selector="app=consul,component=server"'
```

Your VM should be connected to your cluster.