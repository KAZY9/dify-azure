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

@description('Base64 エンコードした cloud-init の内容。')
param customData string

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
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
          storageAccountType: 'Premium_LRS'
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

output vmName string = vm.name
output principalId string = vm.identity.principalId
