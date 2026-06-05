// VM: NIC + Ubuntu 22.04 LTS の仮想マシン
// SSH 鍵認証のみ（パスワード無効）、システム割り当てマネージド ID を有効化。
// customData(cloud-init) で Docker と Dify 公式 compose を起動する。

@description('リソースのデプロイ先リージョン。')
param location string

@description('リソース名のプレフィックス。')
param namePrefix string

@description('NIC を接続するサブネットの ID。')
param subnetId string

@description('割り当てるパブリック IP の ID。')
param publicIpId string

@description('VM の管理者ユーザー名。')
param adminUsername string

@description('管理者ユーザーの SSH 公開鍵。')
param adminPublicKey string

@description('VM サイズ。')
param vmSize string = 'Standard_D4s_v5'

@description('OS ディスクサイズ（GB）。')
param osDiskSizeGB int = 64

@description('OS ディスクのストレージ種別。')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskStorageAccountType string = 'StandardSSD_LRS'

@description('Base64 エンコードした cloud-init の内容。')
param customData string

@description('夜間の自動停止(deallocate)を有効化する。開始は手動運用（az vm start）。')
param enableAutoShutdown bool = true

@description('自動停止の時刻（HHmm 形式, autoShutdownTimeZone 基準）。例: 1900 = 19:00。')
param autoShutdownTime string = '1900'

@description('自動停止のタイムゾーン（Windows タイムゾーン ID）。JST は Tokyo Standard Time。')
param autoShutdownTimeZone string = 'Tokyo Standard Time'

resource nic 'Microsoft.Network/networkInterfaces@2024-07-01' = {
  name: '${namePrefix}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${namePrefix}-vm'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${namePrefix}-vm'
      adminUsername: adminUsername
      customData: customData
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
        managedDisk: {
          storageAccountType: osDiskStorageAccountType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// 夜間に VM を deallocate する自動停止スケジュール。
// 名前は 'shutdown-computevm-<vmName>' 形式にすると VM ブレードの Auto-shutdown に表示される。
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (enableAutoShutdown) {
  name: 'shutdown-computevm-${vm.name}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimeZone
    notificationSettings: {
      status: 'Disabled'
    }
    targetResourceId: vm.id
  }
}

output vmName string = vm.name
output principalId string = vm.identity.principalId
