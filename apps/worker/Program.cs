using Azure.Storage.Blobs;
using Data;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Worker.Services;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration["ConnectionStrings:AppDb"]));

builder.Services.AddSingleton(_ =>
    new BlobServiceClient(builder.Configuration["ConnectionStrings:AzureStorage"]));

var visionEndpoint = builder.Configuration["VisionModel:Endpoint"];
var visionModel = builder.Configuration["VisionModel:Model"];
if (string.IsNullOrEmpty(visionEndpoint) || string.IsNullOrEmpty(visionModel))
{
    throw new InvalidOperationException(
        "VisionModel:Endpoint and VisionModel:Model must be configured — the worker classifies " +
        "and describes images with the vision model. See .devcontainer/docker-compose.yml.");
}

builder.Services.AddSingleton(_ =>
{
    var httpClient = new HttpClient
    {
        BaseAddress = new Uri(visionEndpoint),
        // A 4B model on CPU can take a while on a large photo.
        Timeout = TimeSpan.FromMinutes(2)
    };
    return new ImageAnalyzer(httpClient, visionModel);
});

builder.Build().Run();
