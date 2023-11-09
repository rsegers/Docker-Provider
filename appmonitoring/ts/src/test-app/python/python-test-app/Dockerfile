# Use an official Python runtime as a base image
FROM python:3.9-slim

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install the required packages
RUN pip install --no-cache-dir -r requirements.txt

# Copy the current directory contents into the container
COPY main.py .
COPY sitecustomize.py /app/data/sitecustomize.py

# Make port 5000 available to the world outside this container
EXPOSE 80

# Define environment variable to ensure Flask runs in production mode
ENV FLASK_ENV=production


# Run app.py when the container launches
CMD ["python", "./main.py"]
