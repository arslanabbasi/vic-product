oneGB = 1 * 1000 * 1000 # in KB
 
$testbed = Proc.new do
  {
    "name" => "vic-nfs-cluster",
    "version" => 3,
    "esx" => (0..1).map do | idx |
      {
        "name" => "esx.#{idx}",
        "vc" => "vc.0",
        'cpus' => 8,
        'cpuReservation' => 4800,
        "style" => "fullInstall",
        "desiredPassword" => "ca$hc0w",
        "memory" => 32768, # 2x default
        'memoryReservation' => 16384,
        "disk" => [ 100 * oneGB, 100 * oneGB],
        "nics" => 2,
        "mountNfsWithPath" => true,
        "mountNfs" => ["nfs.0:/exports/nfs-share"],
        "clusterName" => "cls1",
      }
    end,

    "nfs" => [
      {
        "name" => "nfs.0",
        "type" => "NFS41",
        "disks" => [400 * oneGB],
        "mountPoints" => ["nfs-share"]
      }
    ],

    "vcs" => [
      {
        "name" => "vc.0",
        "type" => "vcva",
        'cpuReservation' => 2400,
        'memoryReservation' => 4096,
        "dcName" => "dc1",
        "clusters" => [{"name" => "cls1", "vsan" => false, "enableDrs" => true, "enableHA" => true}],
        "addHosts" => "allInSameCluster",
      }
    ],

    "postBoot" => Proc.new do |runId, testbedSpec, vmList, catApi, logDir|
      esxList = vmList['esx']
        esxList.each do |host|
          host.ssh do |ssh|
            ssh.exec!("esxcli network firewall set -e false")
          end
      end
      vc = vmList['vc'][0]
      vim = VIM.connect vc.rbvmomiConnectSpec
      datacenters = vim.serviceInstance.content.rootFolder.childEntity.grep(RbVmomi::VIM::Datacenter)
      raise "Couldn't find a Datacenter precreated"  if datacenters.length == 0
      datacenter = datacenters.first
      Log.info "Found a datacenter successfully in the system, name: #{datacenter.name}"
      clusters = datacenter.hostFolder.children
      raise "Couldn't find a cluster precreated"  if clusters.length == 0
      cluster = clusters.first
      Log.info "Found a cluster successfully in the system, name: #{cluster.name}"

      dvs = datacenter.networkFolder.CreateDVS_Task(
        :spec => {
          :configSpec => {
            :name => "test-ds"
          },
	    }
      ).wait_for_completion
      Log.info "Vds DSwitch created"

      dvpg1 = dvs.AddDVPortgroup_Task(
        :spec => [
          {
            :name => "management",
            :type => :earlyBinding,
            :numPorts => 12,
          }
        ]
      ).wait_for_completion
      Log.info "management DPG created"

      dvpg2 = dvs.AddDVPortgroup_Task(
        :spec => [
          {
            :name => "vm-network",
            :type => :earlyBinding,
            :numPorts => 12,
          }
        ]
      ).wait_for_completion
      Log.info "vm-network DPG created"

      dvpg3 = dvs.AddDVPortgroup_Task(
        :spec => [
          {
            :name => "bridge",
            :type => :earlyBinding,
            :numPorts => 12,
          }
        ]
      ).wait_for_completion
      Log.info "bridge DPG created"

      Log.info "Add hosts to the DVS"
      onecluster_pnic_spec = [ VIM::DistributedVirtualSwitchHostMemberPnicSpec({:pnicDevice => 'vmnic1'}) ]
      dvs_config = VIM::DVSConfigSpec({
        :configVersion => dvs.config.configVersion,
        :host => cluster.host.map do |host|
        {
          :operation => :add,
          :host => host,
          :backing => VIM::DistributedVirtualSwitchHostMemberPnicBacking({
            :pnicSpec => onecluster_pnic_spec
          })
        }
        end
      })
      dvs.ReconfigureDvs_Task(:spec => dvs_config).wait_for_completion
      Log.info "Hosts added to DVS successfully"
    end
  }
end

