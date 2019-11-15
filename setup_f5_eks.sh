#!/bin/bash

function print_usage() {
  CMD="$1"
  ERROR_MSG="$2"

  if [ "$ERROR_MSG" != "" ]; then
    echo -e "\nERROR: $ERROR_MSG"
  fi

  echo -e "\nUse this script to install Fusion 5 on EKS; optionally create a EKS cluster in the process. We are using 1 vpc and 2 subnets from different AZs\n"
  echo -e "\nUsage: $CMD [OPTIONS] ... where OPTIONS include:\n"
  echo -e "  -c          Name of the EKS cluster (required)\n"
  echo -e "  -p          AWS_ACCOUNT - profile (required)\n"
  echo -e "  -r          Helm release name for installing Fusion 5, defaults to 'f5'\n"
  echo -e "  -n          Kubernetes namespace to install Fusion 5 into, defaults to 'default'\n"
  echo -e "  -z          AWS Region to launch the cluster in, defaults to 'us-west-2'\n"
  echo -e "  -i          Instance type, defaults to 'm5.2xlarge'\n"
  echo -e "  -a          AMI to use for the nodes, defaults to 'auto'\n"
  echo -e "  --version   Fusion Helm Chart version, defaults to 5.0.2-3\n"
  echo -e "  --values    Custom values file containing config overrides; defaults to eks_<cluster>_<release>_fusion_values.yaml\n"
  echo -e "  --create    Create a cluster in EKS; provide the mode of the cluster to create, one of: demo\n"
  echo -e "  --upgrade   Perform a Helm upgrade on an existing Fusion installation\n"
  echo -e "  --purge     Uninstall and purge all Fusion objects from the specified namespace and cluster\n"
}

SCRIPT_CMD="$0"
AWS_ACCOUNT=
REGION=us-west-2
CLUSTER_NAME=
RELEASE=f5
NAMESPACE=default
UPGRADE=0
CREATE_MODE=
PURGE=0
INSTANCE_TYPE="m5.2xlarge"
CHART_VERSION="5.0.2-7"
AMI="auto"
CUSTOM_MY_VALUES=""
ML_MODEL_STORE="fusion"

if [ $# -gt 0 ]; then
  while true; do
    case "$1" in
        -c)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -c parameter!"
              exit 1
            fi
            CLUSTER_NAME="$2"
            shift 2
        ;;
        -n)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -n parameter!"
              exit 1
            fi
            NAMESPACE="$2"
            shift 2
        ;;
        -p)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -p parameter!"
              exit 1
            fi
            AWS_ACCOUNT="$2"
            shift 2
        ;;
        -r)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -r parameter!"
              exit 1
            fi
            RELEASE="$2"
            shift 2
        ;;
        -z)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -z parameter!"
              exit 1
            fi
            REGION="$2"
            shift 2
        ;;
        -i)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -i parameter!"
              exit 1
            fi
            INSTANCE_TYPE="$2"
            shift 2
        ;;
        -a)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the -a parameter!"
              exit 1
            fi
            AMI="$2"
            shift 2
        ;;
        --version)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --version parameter!"
              exit 1
            fi
            CHART_VERSION="$2"
            shift 2
        ;;
        --values)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --values parameter!"
              exit 1
            fi
            CUSTOM_MY_VALUES="$2"
            shift 2
        ;;
        --create)
            if [[ -z "$2" || "${2:0:1}" == "-" ]]; then
              print_usage "$SCRIPT_CMD" "Missing value for the --create parameter!"
              exit 1
            fi
            CREATE_MODE="$2"
            shift 2
        ;;
        --upgrade)
            UPGRADE=1
            shift 1
        ;;
        --purge)
            PURGE=1
            shift 1
        ;;
        -help|-usage)
            print_usage "$SCRIPT_CMD"
            exit 0
        ;;
        --)
            shift
            break
        ;;
        *)
            if [ "$1" != "" ]; then
              print_usage "$SCRIPT_CMD" "Unrecognized or misplaced argument: $1!"
              exit 1
            else
              break # out-of-args, stop looping
            fi
        ;;
    esac
  done
fi

if [ "$CREATE_MODE" != "" ] && [ "$UPGRADE" == "1" ]; then
  print_usage "$SCRIPT_CMD" "Must specify either the --create or --upgrade options but not both!"
  exit 1
fi

if [ "$CLUSTER_NAME" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the EKS cluster name using: -c <cluster>"
  exit 1
fi

if [ "$AWS_ACCOUNT" == "" ]; then
  print_usage "$SCRIPT_CMD" "Please provide the AWS project name using: -p <project>"
  exit 1
fi

MY_VALUES="eks_${CLUSTER_NAME}_${RELEASE}_fusion_values.yaml"

if [ -n "$CUSTOM_MY_VALUES" ]; then
  MY_VALUES=$CUSTOM_MY_VALUES
fi

hash kubectl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install kubectl before proceeding with this script! See: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
  exit 1
fi

hash helm
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install helm before proceeding with this script! See: https://helm.sh/docs/using_helm/#quickstart"
  exit 1
fi

hash aws
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install aws cli tools before proceeding with this script! See: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html"
  exit 1
fi

hash eksctl
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install eksctl before proceeding with this script! See: https://docs.aws.amazon.com/eks/latest/userguide/getting-started-eksctl.html"
  exit 1
fi

hash aws-iam-authenticator
has_prereq=$?
if [ $has_prereq == 1 ]; then
  echo -e "\nERROR: Must install aws-iam-authenticator before proceeding with this script! See: https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html"
  exit 1
fi

# verify the user is logged in ...
who_am_i=$(aws --profile "${AWS_ACCOUNT}" --region "${REGION}" sts get-caller-identity --query "Arn"  --output text)
if [ "${who_am_i}" == "" ]; then
  echo -e "\nERROR: AWS user unknown, please use: 'aws configure' before proceeding with this script!"
  exit 1
fi

echo -e "\nLogged in as: $who_am_i\n"

is_helm_v3=$(helm version --short | grep v3)

if [ "$PURGE" == "1" ]; then
  aws eks --region "${REGION}" update-kubeconfig --name "${CLUSTER_NAME}"
  current=$(kubectl config current-context)
  confirm="Y"
  read -p "Are you sure you want to purge the ${RELEASE} release from the ${NAMESPACE} namespace in: $current? This operation cannot be undone! Y/n " confirm
  if [ "$confirm" == "" ] || [ "$confirm" == "Y" ] || [ "$confirm" == "y" ]; then
    if [ "$is_helm_v3" != "" ]; then
      helm delete ${RELEASE}
    else
      helm del --purge ${RELEASE}
    fi
    kubectl delete deployments -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete job "${RELEASE}-api-gateway" --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=1s
    kubectl delete svc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=2s
    kubectl delete pvc -l app.kubernetes.io/part-of=fusion --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l release="${RELEASE}" --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
    kubectl delete pvc -l app.kubernetes.io/instance="${RELEASE}" --namespace "${NAMESPACE}" --grace-period=0 --force --timeout=5s
  fi
  exit 0
fi

aws eks --profile "${AWS_ACCOUNT}" --region "${REGION}" list-clusters --query "clusters" |  grep "${CLUSTER_NAME}" > /dev/null 2>&1
cluster_status=$?
if [ "$cluster_status" != "0" ]; then
  if [ "$CREATE_MODE" == "" ]; then
    CREATE_MODE="demo" # the default ...
  fi

  echo -e "\nLaunching an EKS cluster ${CLUSTER_NAME} ($CREATE_MODE) in project ${AWS_ACCOUNT} for deploying Lucidworks Fusion 5 ...\n"
  if [ "$CREATE_MODE" == "demo" ] || [ "${CREATE_MODE}"  == "multi_az" ]; then
     #Creates EKS cluster
     cat << EOF | eksctl create cluster --profile "${AWS_ACCOUNT}" --config-file - 
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${REGION}

nodeGroups:
  - name: standard-workers
    instanceType: ${INSTANCE_TYPE}
    desiredCapacity: 3
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
    ami: ${AMI}
    maxSize: 6
    minSize: 0

EOF

  else
    echo -e "\nNo --create arg provided, assuming you want a multi-AZ, multi-NodePool cluster ..."
    echo -e "Clusters with multiple NodePools not supported by this script yet! Please create the cluster and define the NodePools manually.\n"
    exit 1
  fi

  echo -e "\nCluster '${CLUSTER_NAME}' deployed ... testing if it is healthy"
  cluster_status=$(aws eks --profile "${AWS_ACCOUNT}" --region "${REGION}" describe-cluster --name "${CLUSTER_NAME}" --query "cluster.status" )
  if [ "$cluster_status" != '"ACTIVE"' ]; then
    echo -e "\nERROR: Status of EKS cluster ${CLUSTER_NAME} is suspect, status is: ${cluster_status}, check the AWS console before proceeding!\n"
    exit 1
  fi
else
  if [ "$UPGRADE" == "0" ]; then
    echo -e "\nEKS Cluster '${CLUSTER_NAME}' already exists, proceeding with Fusion 5 install ...\n"
  fi
fi

function report_ns() {
  if [ "${NAMESPACE}" != "default" ]; then
    echo -e "\nNote: Change the default namespace for kubectl to ${NAMESPACE} by doing:\n    kubectl config set-context --current --namespace=${NAMESPACE}\n"
  fi
}

function proxy_url() {
  PROXY_HOST=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  PROXY_PORT=$(kubectl --namespace "${NAMESPACE}" get service proxy -o jsonpath='{.spec.ports[?(@.protocol=="TCP")].port}')
  export PROXY_URL="$PROXY_HOST:$PROXY_PORT"
  if [ "$PROXY_URL" != ":" ]; then
    echo -e "\n\nFusion 5 Gateway service exposed at: $PROXY_URL\n"
    echo -e "WARNING: This IP address is exposed to the WWW w/o SSL! This is done for demo purposes and ease of installation.\nYou are strongly encouraged to configure a K8s Ingress with TLS, see:\n   https://aws.amazon.com/premiumsupport/knowledge-center/terminate-https-traffic-eks-acm/"
    echo -e "\nAfter configuring an Ingress, please change the 'proxy' service to be a ClusterIP instead of LoadBalancer\n"
    report_ns
   else
    echo -e "\n\nFailed to get Fusion Gateway service URL! Check console for previous errors.\n"
   fi
}

#Updates kubeconfig
aws eks --region "${REGION}" update-kubeconfig --name "${CLUSTER_NAME}"
current_cluster=$(kubectl config current-context)
echo -e "\nConfigured to use EKS cluster: ${current_cluster}"

kubectl rollout status "deployment/${RELEASE}-query-pipeline" -n "${NAMESPACE}" --timeout=10s > /dev/null 2>&1
rollout_status=$?
if [ $rollout_status == 0 ]; then
  if [ "$UPGRADE" == "0" ]; then
    echo -e "\nLooks like Fusion is already running ..."
    proxy_url
    exit 0
  fi
fi

if [ "$UPGRADE" == "0" ]; then
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin \
    --user="$(aws --profile "${AWS_ACCOUNT}" --region "${REGION}" sts get-caller-identity --query "Arn")"
fi

if [ "${is_helm_v3}" == "" ]; then
  # see if Tiller is deployed ...
  kubectl rollout status deployment/tiller-deploy --timeout=10s -n kube-system > /dev/null 2>&1
  rollout_status=$?
  if [ $rollout_status != 0 ]; then
    echo -e "\nSetting up Helm Tiller ..."
    kubectl create serviceaccount --namespace kube-system tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    helm init --service-account tiller --wait
    helm version
  fi
else
  echo -e "Using Helm V3 ($is_helm_v3), no Tiller to install"
fi

lw_helm_repo=lucidworks

echo -e "\nAdding the Lucidworks chart repo to helm repo list"
helm repo list | grep "https://charts.lucidworks.com"
if [ $? ]; then
  helm repo add "${lw_helm_repo}" https://charts.lucidworks.com
fi

if [ ! -f $MY_VALUES ] && [ "$UPGRADE" != "1" ]; then
  SOLR_REPLICAS=$(kubectl get nodes | grep "$CLUSTER_NAME" | wc -l)
  if [ $SOLR_REPLICAS -eq 0 ]; then
      echo "Hmmn, didn't get a proper count of nodes, will set SOLR_REPLICAS to 1 just to play safe"
      SOLR_REPLICAS=1
  fi

  CREATED_MY_VALUES=1

  tee "${MY_VALUES}" << END
sql-service:
  enabled: false
  replicaCount: 0
  service:
    thrift:
      type: "ClusterIP"

solr:
  image:
    tag: 8.2.0
  updateStrategy:
    type: "RollingUpdate"
  javaMem: "-Xmx3g"
  volumeClaimTemplates:
    storageSize: "50Gi"
  replicaCount: ${SOLR_REPLICAS}
  resources: {}
  zookeeper:
    replicaCount: ${SOLR_REPLICAS}
    resources: {}
    persistence:
      size: 15Gi
    env:
      ZK_HEAP_SIZE: 1G
      ZK_PURGE_INTERVAL: 1

ml-model-service:
  image:
    imagePullPolicy: "IfNotPresent"
  modelRepoImpl: ${ML_MODEL_STORE}
  fs:
    enabled: true

fusion-admin:
  readinessProbe:
    initialDelaySeconds: 180

fusion-indexing:
  readinessProbe:
    initialDelaySeconds: 180

query-pipeline:
  javaToolOptions: "-Dlogging.level.com.lucidworks.cloud=INFO"

END
fi

helm repo update

if [ "$UPGRADE" == "1" ]; then

  VALUES_ARG="--values ${MY_VALUES}"
  if [ ! -f "${MY_VALUES}" ]; then
    echo -e "\nWARNING: Custom values file ${MY_VALUES} not found!\nYou need to provide the same custom values you provided when creating the cluster in order to upgrade.\n"
    exit 1
  fi

  if [ "${DRY_RUN}" == "" ]; then
    echo -e "\nUpgrading the Fusion 5 release ${RELEASE} in namespace ${NAMESPACE} to version ${CHART_VERSION} using ${VALUES_ARG}"
  else
    echo -e "\nSimulating an update of the Fusion ${RELEASE} installation into the ${NAMESPACE} namespace using ${VALUES_ARG}"
  fi

  helm upgrade ${RELEASE} "${lw_helm_repo}/fusion" --namespace "${NAMESPACE}" ${VALUES_ARG} ${DRY_RUN} --version ${CHART_VERSION}
  upgrade_status=$?
  proxy_url
  exit $upgrade_status
fi

echo -e "\nInstalling Fusion 5.0 Helm chart ${CHART_VERSION} into namespace ${NAMESPACE} with release tag: ${RELEASE} using custom values from ${MY_VALUES}"
if [ -n "$CREATED_MY_VALUES" ]; then
  echo -e "\nNOTE: If this will be a long-running cluster for production purposes, you should save the ${MY_VALUES} file in version control.\n"
fi

# wait up to 60s to see the metrics server online
metrics_deployment=$(kubectl get deployment -n kube-system | grep metrics-server | cut -d ' ' -f1 -)
kubectl rollout status deployment/${metrics_deployment} --timeout=60s --namespace "kube-system"

set -e
if [ "$is_helm_v3" != "" ]; then
  if ! kubectl get namespace "${NAMESPACE}"; then
    kubectl create namespace "${NAMESPACE}"
  fi
  # looks like Helm V3 doesn't like the -n parameter for the release name anymore
  helm install ${RELEASE} ${lw_helm_repo}/fusion --timeout=240s --namespace "${NAMESPACE}" --values "${MY_VALUES}" --version ${CHART_VERSION}
else
  helm install ${lw_helm_repo}/fusion --timeout 240 --namespace "${NAMESPACE}" -n "${RELEASE}" --values "${MY_VALUES}" --version ${CHART_VERSION}
fi
set +e

kubectl rollout status "deployment/${RELEASE}-api-gateway" --timeout=600s --namespace "${NAMESPACE}"
kubectl rollout status "deployment/${RELEASE}-fusion-admin" --timeout=600s --namespace "${NAMESPACE}"

proxy_url
