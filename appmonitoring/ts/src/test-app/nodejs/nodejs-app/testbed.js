const http = require('http');
const https = require('https');

const server = http.createServer((req, res) => {
    if (req.url === '/nice' && req.method === 'GET') {
        https.get('https://democoreapp.azurewebsites.net/api/coresource?code=0ftKFXqjhVMVkHXXNGiUuGlbHXbyUOo88TY-IxQI_YlXAzFudrvTuQ%3D%3D&name=Oranges', (response) => {
            let data = '';

            // A chunk of data has been received.
            response.on('data', (chunk) => {
                data += chunk;
            });

            // The whole response has been received.
            response.on('end', () => {
                res.end(data);
            });

        }).on("error", (err) => {
            console.log("Error: " + err.message);
        });
    }
});

const port = 8080;
server.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});
