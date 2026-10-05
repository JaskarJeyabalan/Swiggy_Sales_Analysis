# Forecast check (11 folds, 30-day horizon)

                                MAE  MAPE  WAPE  WAPE_std
model                                                    
Mean of all history         8467.00  3.92  3.90      0.54
Moving avg 28d              8645.86  3.99  3.98      0.56
Moving avg 14d              8772.30  4.05  4.04      0.65
Moving avg 7d               8897.80  4.10  4.10      0.78
Weekday profile (8 weeks)   9022.57  4.17  4.15      0.62
Seasonal naive (7d)        11488.36  5.29  5.28      0.80
Naive (last day)           12099.86  5.55  5.57      2.36

The gap is small. The data is flat, so a plain average is about as good as any model.
