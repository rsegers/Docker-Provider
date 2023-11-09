# Use ASP.NET Core runtime image
FROM mcr.microsoft.com/dotnet/aspnet:7.0 AS runtime
WORKDIR /app

# Copy compiled app to /app directory in the image
COPY ./bin/Debug/net7.0/ ./

# # Set environment variable to tell ASP.NET Core to listen on port 80
# ENV ASPNETCORE_URLS=http://+:5146

# Start the app
ENTRYPOINT ["dotnet", "DemoTestApp.dll"]
