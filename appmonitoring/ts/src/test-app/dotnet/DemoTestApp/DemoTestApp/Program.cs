using System.Net.Http;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = WebApplication.CreateBuilder(args);

// Add the HttpClientFactory to be used for creating HttpClient instances
builder.Services.AddHttpClient();

var app = builder.Build();

app.MapGet("/nice", async (HttpClient client) =>
{
    var response = await client.GetAsync("https://democoreapp.azurewebsites.net/api/coresource?code=0ftKFXqjhVMVkHXXNGiUuGlbHXbyUOo88TY-IxQI_YlXAzFudrvTuQ%3D%3D&name=Oranges");

    if (response.IsSuccessStatusCode)
    {
        return Results.Ok(await response.Content.ReadAsStringAsync());
    }

    return Results.BadRequest();
});

app.Run();
