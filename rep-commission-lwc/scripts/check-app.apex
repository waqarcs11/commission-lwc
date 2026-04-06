List<AppMenuItem> apps = [SELECT Id, Name, Label FROM AppMenuItem WHERE Type = 'CustomApp' ORDER BY Label];
for (AppMenuItem a : apps) {
    System.debug('App: ' + a.Name + ' | Label: ' + a.Label);
}
