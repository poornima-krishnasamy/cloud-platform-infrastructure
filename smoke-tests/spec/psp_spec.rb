require "spec_helper"

# Pod security policies (PSP) is a cluster-level resource that
# controls security sensitive aspects of the pod specification.
# This spec confirms the Cloud Platform psp's are operational
# within its cluster.
describe "pod security policies" do
  let(:namespace) { "integrationtest-psp-#{readable_timestamp}" }
  let(:pods) { get_running_pods(namespace)}

  # Confirms the main psp's currently exist
  specify "has the expected policies" do
    names = get_psp.map { |set| set.dig("metadata", "name") }.sort

    expected = [
      "privileged",
      "restricted",
      "kube-system"
    ]
    expect(names).to include(*expected)
  end

  # Runs a privilege namespace and confirms both privilege and
  # non-privilege containers can run. 
  context "when namespace is privileged" do
    before do
      create_namespace(namespace)
      make_namespace_privileged(namespace)
    end

    after do
      delete_namespace(namespace)
      delete_clusterrolebinding(namespace)
    end

    it "privileged containers run" do
      create_privileged_deploy(namespace)
      # On occasion the expect runs before the container runs.
      # Sleep for ten seconds to avoid this. 
      sleep 10

      expect(all_containers_running?(pods)).to eq(true)
    end

    it "unprivileged containers run" do
      create_unprivileged_deploy(namespace)

      expect(all_containers_running?(pods)).to eq(true)
    end
  end

  # Runs a unprivileged namespace and confirms only
  # on-privilege containers can run. 
  context "when namespace is unprivileged" do
    before do
      create_namespace(namespace)
    end

    after do
      delete_namespace(namespace)
    end

    it "privileged containers fail" do
      create_privileged_deploy(namespace)

      expect(all_containers_running?(pods)).to eq(false)
    end

    it "unprivileged containers run" do
      create_unprivileged_deploy(namespace)

      expect(all_containers_running?(pods)).to eq(true)
    end
  end
end

# Creates a clusterrolebinding between the privileged psp
# and the namespaces default service account.
def make_namespace_privileged(namespace)
  json = <<~EOF
    {
      "apiVersion": "rbac.authorization.k8s.io/v1",
      "kind": "ClusterRoleBinding",
      "metadata": {
          "name": "#{namespace}"
      },
      "roleRef": {
          "apiGroup": "rbac.authorization.k8s.io",
          "kind": "ClusterRole",
          "name": "psp:privileged"
      },
      "subjects": [
          {
              "apiGroup": "rbac.authorization.k8s.io",
              "kind": "Group",
              "name": "system:serviceaccounts:#{namespace}"
          }
      ]
    }
  EOF

  jsn = JSON.parse(json).to_json

  cmd = %(echo '#{jsn}' | kubectl -n #{namespace} apply -f -)
  execute(cmd)
end
