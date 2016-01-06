﻿Configuration MasterConfig
{
    Import-DscResource -Module xDSCMCompositeConfiguration

    Node $AllNodes.NodeName {    
        xDSCMBase BaseConfig
        {
            DNSServerAddresses = $Node.DNSServerAddresses
            Location =$Node.Location
        }
    }

    Node $AllNodes.Where{$_.Service -eq "DC"}.NodeName {
        xDSCMDC DCConfig
        {
            Role = $Node.Role
            DomainName = $Node.DomainName
        }
    }

    Node $AllNodes.Where{$_.Service -eq "SCCM"}.NodeName {
        xDSCMSCCM SCCMConfig
        {
            Role = $Node.Role
            DSLPath = $Node.DSLPath
        }
    }
}
