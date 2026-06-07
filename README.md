# Summary
This script will connect to a Kubex instance and download information on every container running in the environment.  It will then output a list of every cluster, what software was found in it, and the namespacee in which it was found.

## Syntax
`kubex-inventory.ps1 [-user=<username>] [-pass=<instance password>] [-instance <instancenam>] [-baseurl ".kubex.ai" | ".densify.com" ] [-csv]`

All command-line parameters may also be specified in a file named kubex-inventory.ini which must be saved in the same folder as the script.  (Note that the -csv option only works from the command-line.)

## CSV Output
If you specify the -csv option from the command-line all output will be in CSV format for import into Excel.  One line for each Container that matches a known software package.

#### CSV example

`kubex-inventory.ps1 -user "dchase@densify.com" -pass "NotMyPassword" -host "sandbox.kubex.ai" -csv > "Sandbox Software.csv"`

#### Sample command-line
Here is an interesting sample command-line that will scan a customer instance and identify every instance of Kubex Automation components.  This allows you to see if they've upgraded from the Kubex Automation Controller (Deprecated) to the Kubex Automation Engine.

`kubex-inventory.ps1 -instance sandbox | grep "Kubex Automation"`

## How it works
There's no magic going on here.  `software.csv` contains a list of software packages and the matching logic to identify them.  The format of the file is:

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

The software list can detect a few hundred Kubernetes software packages, but it's not even close to complete.  If it's not detecting a piece of software you know is in the cluster, add a signature in `software.csv`.  

Enjoy!
