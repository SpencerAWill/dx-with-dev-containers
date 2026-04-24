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

var modelsPath = Path.Combine(builder.Environment.ContentRootPath, "Models");
builder.Services.AddSingleton(new ImageClassifier(
    Path.Combine(modelsPath, "mobilenetv2-7.onnx"),
    Path.Combine(modelsPath, "imagenet_classes.txt")));

var visionEndpoint = builder.Configuration["VisionModel:Endpoint"];
var visionModel = builder.Configuration["VisionModel:Model"];
if (!string.IsNullOrEmpty(visionEndpoint) && !string.IsNullOrEmpty(visionModel))
{
    builder.Services.AddSingleton(sp =>
    {
        var httpClient = new HttpClient { BaseAddress = new Uri(visionEndpoint) };
        return new ImageDescriber(httpClient, visionModel);
    });
}

builder.Build().Run();
