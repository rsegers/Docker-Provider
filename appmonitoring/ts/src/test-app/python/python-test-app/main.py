from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    app.logger.info("This is working")
    return "Good"

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=80)
