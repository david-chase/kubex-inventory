# Summary
This script will connect to a Kubex instance and show you a list of all the software running in that environment, by cluster and namespace.  It does so by connecting to the instance, running a Graph API query to return every container running in the cluster, then comparing those containers, pods, and namespaces against a known list of software signatures.  It's not fool-proof, but it's a start!

## Syntax
`kubex-inventory.ps1 [-user=<username>] [-pass=<instance password>] [-instance <instancename>] [-baseurl ".kubex.ai" | ".densify.com" ] [-csv]`

## Examples
If you specify the -csv option from the command-line all output will be in CSV format for import into Excel.  One line for each Container that matches a known software package.

#### CSV example
This will save the output in .CSV format for slicing & dicing in Excel.  This is NOT a readable format, it's for generating reports.

`kubex-inventory.ps1 -user "dchase@densify.com" -pass "NotMyPassword" -instance "sandbox" -csv > "Sandbox Software.csv"`

#### Save the output for later
You can pipe the output to a file if you want to save a human-readable copy for later.  (Think before/after comparisons.)

`kubex-inventory.ps1 -instance sandbox > "Sandbox Software Report.txt"`

#### Detecting Kubex Automation upgrade
Here is an interesting sample command-line that will scan a customer instance and identify every instance of Kubex Automation components.  This allows you to see if they've upgraded from the Kubex Automation Controller (Deprecated) to the Kubex Automation Engine.

`kubex-inventory.ps1 -instance sandbox | grep "Kubex Automation"`

## Saving defaults
All command-line parameters may also be specified in a file named `kubex-inventory.ini` which must be saved in the same folder as the script.  

Here's a sample `kubex-inventory.ini`
```
user=dchase@densify.com
pass=NotMyPassword
baseurl=.kubex.ai
```

## How it works
Simple pattern matching.  `software.csv` contains a list of software packages and the matching logic to identify them.  The format of the file is:

`<Software Package>, <Software Category>, "<Matching rule>"`

Matching rules must be surrounded by double quotes and are in the format:

`"<Object Type> <Operator> <String>"`

**Object Type** can be "namespace", "pod", or "container".<br>
**Operator** can be "Equals", "DoesntEqual", "Contains", "DoesntContain", "StartsWith", "DoesntStartWith", "EndsWith", or "DoesntEndWith".<br>
**String** is the string to match.

All values in `software.csv` are case insensitive.

#### Matching rule examples
```
Karpenter, Node Autoscaler, "container Equals karpenter"
Kubescape, Security Suite, "pod Contains kubescape"
Kubex, Kubernetes Optimization, "container StartsWith kubex"
```

## Disclaimers
The tool doesn't output software versions -- that data doesn't exist in the Kubex schema.

The tool can't detect software that runs as a native sidecar because Kubex doesn't collect data for init containers.

The software list can detect a few hundred Kubernetes software packages, but it's not even close to complete.  If it's not detecting a piece of software you know is in the cluster, add a signature in `software.csv`.  

Enjoy!
