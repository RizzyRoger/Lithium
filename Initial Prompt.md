# Context:
1. I need an app to limit the time I have on any site for the day
# Features of the app:
1. I should be able to set daily limits on any kind of website, by inputting the url and the 
2. If no limit is set, it should not have any restrictions on that website. 
3. Limits should be able to be set cross browser. Thats why it should be an app instead of a browser extension, because the browser extension would not work cross browsers, and could be easily circumvented.
4. I should be able to set time limits, or just ban entirely from the day.
5. The app should be effective in blocking the site, when reaching a site that ran out of time for the day, or was blocked, it should redirect to saying "Site Blocked for the day"
# UI layout: 
1. This app should be a status item along the menu bar extras at the top of the page. The app itself should just open and configure the top menu bar status item.
2. When clicked on the status item, it should have 2 sections. The top one should be set restrictions. When clicked it should open a dropdown of both how long per day in mins and hours and what the site link is
3. When inputting what the site link is, it should have autofill options. For example if i typed in tik, it could determine that i probubly mean tiktok.
4. The bottom section should have a "save current config as preset" You should be able to name and swap between presets like that, to be able to save something to be used for later
# Importaint!
1. If you need clarification, just ask
2. If anything breaks, reflect on 5-7 different possible sources of the problem, distill those down to 1-2 most likely sources, and then add logs to validate your assumptions before we move onto implementing the actual code fix