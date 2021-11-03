# Disclaimer

THE SAMPLE CODE ON THIS REPOSITORY IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.

THE USAGE OF THIS SAMPLE IS AT YOUR OWN RISK AND **THERE IS NO SUPPORT** RELATED TO IT.

# Description
The coolorange.flc.sync.changeorder.items workflow can be used to change Vault item states based on the state of a Fusion change order.

# Requirements
* All Vault items that should be controlled by the job need to be in the same lifecycle
* The user that executes the job needs special permission to execute all possible lifecycle state changes. The job doesn't check if an attempted state change is valid and will fail if permissions are missing.

# Configuration
## powerFLC Workflow
* **ItemLifeCycle**: This is the life cycle the controlled items need to be in
* For each transition that the job is supposed to execute there needs to be an **FLC State** setting and a matching **Vault Lifecycle State** setting. The two settings must have identical names.

# How to use


# At your own risk
The usage of these samples is at your own risk. There is no free support related to the samples. However, if you have questions to powerJobs, then visit http://www.coolorange.com/wiki or start a conversation in our support forum at http://support.coolorange.com/support/discussions

# Author
coolOrange s.r.l.

![coolOrange](https://i.ibb.co/NmnmjDT/Logo-CO-Full-colore-RGB-short-Payoff.png)
