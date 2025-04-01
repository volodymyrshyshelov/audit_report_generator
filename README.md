# 🛡️ Audit Report Generator

## Overview
This PowerShell script automates system audits and generates a professional MS Word report. It leverages the `PSWriteWord` module and allows customization via a `config.json` file.

## 🚀 Features
- Automates auditing tasks based on predefined controls.
- Generates a structured MS Word audit report.
- Customizable through a JSON configuration file.

## ⚙️ Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/volodymyrshyshelov/AuditReportGenerator.git
   cd AuditReportGenerator
   ```
2. Install the required PowerShell module:
   ```powershell
   Install-Module -Name PSWriteWord -Force -Scope CurrentUser
   ```

## 📌 Usage
1. Edit the `config.json` file to define controls and the output path.
2. Run the script:
   ```powershell
   .\AuditReportGenerator.ps1
   ```
3. The report will be saved in the specified output directory.

## 🛠️ Configuration
The `config.json` file contains:
- **OutputPath**: Directory where the report will be saved.
- **Controls**: List of controls to audit, each with:
  - `Name`: Control name
  - `Profile`: Applicability (e.g., L1, L2)
  - `Description`: Brief explanation
  - `Rationale`: Reasoning behind the control
  - `Impact`: Potential risks if not implemented
  - `AuditCommand`: PowerShell command to audit the control
  - `References`: Additional resources

## 📄 Example Output
The generated MS Word report will include:
```
Audit Report
Audit Date: YYYY-MM-DD

[Control]: Control Name
Profile Applicability: L1
Description: Restrict the use of removable media.
Rationale: Prevents unauthorized data transfer.
Impact: High risk of data leakage.
Audit Output: [Command Result]
References: https://docs.microsoft.com/security
```

## 📜 License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
