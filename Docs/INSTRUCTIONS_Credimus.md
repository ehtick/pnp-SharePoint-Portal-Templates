
# Installation Instructions

Installing the Credimus site requires several steps:

- Create a new Communication Site in your tenant
- Run the PowerShell script to apply the PnP Provisioning template
- Configure the Brand Center
- Configure Viva Connections
- Configure the Credimus site

![Credimus Home Page](./media/instructions-credimus-home-page.jpg)

These installation instructions are streamlined as much as possible, with the goal to get you from start to finish as quickly as possible. If you encounter a topic with which you are not familiar, the instructions link out to Microsoft Learn articles with more specifics.

## Prerequisites

For most of these instructions, you should have the SharePoint Admin role. While some steps can be accomplished by the Site Owner, it will be most expeditious to follow all the instructions with the SharePoint Admin role.

Any exceptions to the above (for example, where Global Administrator permissions are required) are noted in each step.

## Prepare

### Create a new Communication Site

Create a new Communication Site named *Credimus*, using the default template. If you need instructions to create this site, please refer to the support article [Create a communication site in SharePoint](https://support.microsoft.com/office/create-a-communication-site-in-sharepoint-7fb44b20-a72f-4d2c-9173-fc8f59ba50eb)

Be sure to make yourself the Site Owner of the Communication Site. You can add additional Site Owners or Site Members now or later in the site itself.

Throughout the rest of these instructions, you will be either making changes to this site or setting up artifacts in other locations which will support this site, its branding, and its functionality.

### Download ZIP file

### Extract all files in ZIP file

>Note: The ZIP file contains additional files, should you want to automate more of the implementation. These files can also be used as documentation for the process, in addition to these instructions.

We recommend you extract the ZIP file into a folder in the root of your machine, for example */code/Credimus*. This will ensure that the folder paths won't be too long for the script to run successfully.

## Apply PnP Provisioning template

A PowerShell script M365lpConfiguration.ps1 is included that you will need to execute to create three tenant properties that the solution uses. In addition, the script creates two single part app pages in the site pages library to host the admin and user web parts at a known location. This script was built to use PnP PowerShell. Ensure that you can run basic commands and connect before running the Learning Pathways installation script.

The base definition for the site is contained the a PnP Provisioning export file. This file can be found in the folder *PnP Provisioning*, and is named *PnP-Provisioning-CredimusSite.pnp*.

The script *ApplyPnPProvisioningTemplate-Credimus.ps1* applies the PnP Provisioning template to the site you have created above. The template contains information about the lists and libraries, pages, and images contained in the site.

The script also uploads some additional files to the site which cannot be contained in the PnP Provisioning template for technical reasons.

To run the script, open it in Visual Studio Code

[[More details!]]

## Run some PowerShell to get additional "stuff" in place [e.g., automate what we feel we can]

### Upload additional files (not contained in the template)

### Change additional settings



## Configure Brand Center

In order for the site to look like what you see in the screenshots, you'll need to make a set of configurations in the Brand Center. We've made sure to suggest naming conventions which allow you to easily identify where the configuration settings have come from and how they are used, specifically with prefixes which reflect the demo site's name.

If your tenant does not have a Brand Center already, see the article [SharePoint brand center](https://learn.microsoft.com/sharepoint/brand-center-overview). Setting up a Brand Center requires Global Administrator permissions.

If you already have a Brand Center, the default location is */sites/BrandGuide*, though yours may be in a location you chose when you set it up.

### Create theme colors

For this site, you should add the following colors into your Brand Colors. Each is prefixed with the name of the site so you can identify them easily. Note that there is no way to remove Brand Colors in the UI, though you can do so with PowerShell. For detailed instructions, see [Brand Colors](https://learn.microsoft.com/sharepoint/brand-colors).

| Color Name | Color Code | Color |
|---|---|---|
| Credimus.DarkTeal | #022C22 | <span style="display:inline-block; width:20px; height:20px; background-color:#022C22; border:1px solid #000;"></span> |
| Credimus.DeepEmerald | #059669 | <span style="display:inline-block; width:20px; height:20px; background-color:#059669; border:1px solid #000;"></span> |
| Credimus.CyanEdge | #06B6D4 | <span style="display:inline-block; width:20px; height:20px; background-color:#06B6D4; border:1px solid #000;"></span> |
| Credimus.Carbon | #0A0F0D | <span style="display:inline-block; width:20px; height:20px; background-color:#0A0F0D; border:1px solid #000;"></span> |
| | |

### Set up theme

Once you have the Brand Colors defined, you use them to set up a theme. For detailed instructions, see [Site theme](https://learn.microsoft.com/sharepoint/site-theme).

#### Add the theme colors

First, you add the colors to the theme. Add the colors in the order listed above.

![](./media/instructions-credimus-add-theme-colors.jpg)

#### Name the theme

Next, give the theme the name *Credimus.Theme*, and save.
![](./media/instructions-credimus-name-theme.jpg)

#### Review the theme

Finally, the theme should look like this is you have set it up correctly.
![](./media/instructions-credimus-view-theme.jpg)

### Upload fonts

The site uses several custom fonts to enhance its look and feel In this session, you'll upload specific font files to support the site. These font files are not prefixed. For each font family, we need to upload a set of font files, each oof which contains variants on the font for use the Font Package, which we will create next. For detailed instructions, see [Brand Fonts](https://learn.microsoft.com/sharepoint/brand-fonts).

Credimus uses the custom fonts *DM Sans* and *Playfair*. The appropriate files are in the *Fonts* folder.

### Create Font Package

Font Packages combine sets of fonts for use in a site which has the Font Package enabled. For detailed instructions, see [Font packages](https://learn.microsoft.com/sharepoint/brand-center-font-packages).

| Font Slot | Font Name | Font Variant |
|---|---|---|
| Title | DM Sans | ExtraBold |
| Headline | DM Sans | Bold |
| Body | Playfair | Medium |
| Interactive | DM Sans | Bold |
| | | |

#### Choose your fonts

![](./media/instructions-credimus-choose-your-fonts.jpg)


#### Assign your fonts

![](./media/instructions-credimus-assign-your-fonts.jpg)

#### Give your package a name

![](./media/instructions-credimus-give-your-package-a-name.jpg)

### Review font package

Review the settings to ensure you have created the Font Package correctly.

![](./media/instructions-credimus-review-font-package.jpg)



## Viva Connections

Viva Connections - coon to be renamed SharePoint Connections - enables us to create experiences for use in a site or sites. By enabling the experience in a site, you can use the Dashboard Web Part in pages to provide ACES.

### Create Viva Connections experience for site

## Final site configuration

These final steps apply the configurations you have set up above in the site itself.

### Change the look

Go  to the gear, and Select Change the look.

#### Apply theme

Select Theme and choose the Credimus.Theme and Save.

![Apply Credimus Theme](./media/instructions-credimus-set-theme.jpg)

#### Apply Font Package

Enable the Font Package you created above under Fonts.

![Apply Credimus Font Package](./media/instructions-credimus-apply-font-package.jpg)


#### Change Header settings

For this site, the Header settings should be as follows:

| Property Panel | Setting | Value |
|---|---|---|
| Layout | Extended | NA |
| Design | Image | CredimusHeader.png |
| Design | Overlay opacity | 19 |
| Design | Site title visibility | Off |
| Design | Site logo thumbnail | CredimusLogoThumbnail.png |
| Design | Site logo | CredimusLogo.png |
| | | |

The images can be found in the *Header Images* folder.


### Edit home page

#### Add dashboard actions

In the home page of the site, find the Dashboard Web Part. If you'd like to match the ACES you'vve seen in the demo site, you can set them up following the instructions in the following table. If you'd like to customize oit for your organization, you may choose to add ACES which reflect that thinking.

| Link Name | Link Settings |
|---|---|
| | |




