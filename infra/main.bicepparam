using './main.bicep'

param namePrefix = 'dify'
param adminUsername = 'azureuser'

// 自分のグローバル IP に絞る（例: 203.0.113.10/32）。0.0.0.0/0 は SSH を全開放するので避ける。
param allowedSshSourceCidr = '<YOUR_IP>/32'

// SSH 公開鍵の内容を貼り付け（例: `cat ~/.ssh/id_ed25519.pub`）。
param adminPublicKey = '<PASTE_SSH_PUBLIC_KEY>'

param vmSize = 'Standard_D4s_v5'
param osDiskSizeGB = 64
param deployKeyVault = true
