/**************************************************************************
 *                             CS:GO COLORS                               *
 *                     Автор: Феникс(komashchenko)                        *
 *                            Version: 1.3                                *
 *                  http://zizt.ru/  http://hlmod.ru/                     *
 * 03.07.2014 - V1.0: Релиз                                               *
 * 13.10.2014 - V1.1: Обнова                                              *
 * 24.10.2014 - V1.2: Обнова                                              *
 * 17.11.2014 - V1.3: Исправление ошибок                                  *
 **************************************************************************/

#define ZCOLOR 13
 
static const String:color_t[ZCOLOR][] = {"{DEFAULT}", "{RED}", "{LIGHTPURPLE}", "{GREEN}", "{LIME}", "{LIGHTGREEN}", "{LIGHTRED}", "{GRAY}", "{LIGHTOLIVE}", "{OLIVE}", "{LIGHTBLUE}", "{BLUE}", "{PURPLE}"},
	String:color_c[ZCOLOR][] = {"\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07", "\x08", "\x09", "\x10", "\x0B", "\x0C", "\x0E"};
 

stock CGOPrintToChat(client, const String:message[], any:...)
{
	new a = strlen(message)+190, l;
	decl String:b[a];
	l = ReplaceString(b, VFormat(b, a, message, 3), "\n", "~", false);
	for(new i=0; i < ZCOLOR; i++) ReplaceString(b, a, color_t[i], color_c[i]);
	if(l)
	{
		decl String:s[l+1][192];
		for (new m = ExplodeString(b, "~", s, l, 192), p; p < m; p++) PrintToChat(client, " %s", s[p]);
	}
	else  PrintToChat(client, " %s", b);
}

stock CGOPrintToChatAll(const String:message[], any:...)
{
	new a = strlen(message)+190, l;
	decl String:b[a];
	l = ReplaceString(b, VFormat(b, a, message, 2), "\n", "~", false);
	for(new i=0; i < ZCOLOR; i++) ReplaceString(b, a, color_t[i], color_c[i]);
	if(l)
	{
		decl String:s[l+1][192];
		for (new m = ExplodeString(b, "~", s, l, 192), p; p < m; p++) PrintToChatAll(" %s", s[p]);
	}
	else  PrintToChatAll(" %s", b);
}

stock CGOReplaceColorSay(String:text[], maxlength) for(new i=0; i < ZCOLOR; i++) ReplaceString(text, maxlength, color_t[i], color_c[i]);

stock GOPrintToChat(client, const String:message[], any:...)
{
	new a = strlen(message)+190, l;
	decl String:b[a];
	if(l = ReplaceString(b, VFormat(b, a, message, 3), "\n", "~", false))
	{
		decl String:s[l+1][192];
		for (new m = ExplodeString(b, "~", s, l, 192), p; p < m; p++) PrintToChat(client, s[p]);
	}
	else  PrintToChat(client, b);
}

stock GOPrintToChatAll(const String:message[], any:...)
{
	new a = strlen(message)+190, l;
	decl String:b[a];
	if(l = ReplaceString(b, VFormat(b, a, message, 2), "\n", "~", false))
	{
		decl String:s[l+1][192];
		for (new m = ExplodeString(b, "~", s, l, 192), p; p < m; p++) PrintToChatAll(s[p]);
	}
	else  PrintToChatAll(b);
}

stock CGOPrintHintText(client, const String:message[], any:...)
{
	new size = strlen(message)+190;  
	decl String:text[size];
	VFormat(text, size, message, 3);
	if(ReplaceString(text, size, "{{", "<font color='") && ReplaceString(text, size, "}}", "</font>")) ReplaceString(text, size, "==", "'>");
	PrintHintText(client, text);
}

stock CGOPrintHintTextToAll(const String:message[], any:...)
{
	new size = strlen(message)+190;  
	decl String:text[size];
	VFormat(text, size, message, 2);
	if(ReplaceString(text, size, "{{", "<font color='") && ReplaceString(text, size, "}}", "</font>")) ReplaceString(text, size, "==", "'>");
	PrintHintTextToAll(text);
}

stock CGOReplaceColorHsay(String:sText[], size) if(ReplaceString(text, size, "{{", "<font color='") && ReplaceString(text, size, "}}", "</font>")) ReplaceString(text, size, "==", "'>");