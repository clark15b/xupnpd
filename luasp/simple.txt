<?# This is comment ?>

<html>
<head><title>Hello from luasp</title></head>

<body>

Session: <?=env.session?><br>

<?print('Your IP address: '..env.remote_ip)?><br>

URI: <?=env.uri?><br>

</body>

</html>

